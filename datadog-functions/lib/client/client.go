package client

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	datadog "github.com/DataDog/datadog-api-client-go/v2/api/datadog"
	"github.com/oracle/oci-go-sdk/v65/common"
	"github.com/oracle/oci-go-sdk/v65/common/auth"
	"github.com/oracle/oci-go-sdk/v65/objectstorage"
)

var cache *DatadogClient

type apiClient interface {
	CallAPI(req *http.Request) (*http.Response, error)
	PrepareRequest(ctx context.Context, path string, method string, postBody interface{}, headerParams map[string]string, queryParams url.Values, formParams url.Values, fileName *datadog.FormFile) (*http.Request, error)
}

type DatadogClient struct {
	client      apiClient
	apiKey      string
	vaultRegion string
	secretOCID  string
}

// SendMessageToDatadog sends a message to Datadog (the forward path). extraHeaders
// are merged into the request headers and can be used to pass caller-specific
// metadata (e.g. "Dd-Oci-Tenancy-Id"). A 403 triggers an API-key refresh and one
// retry (handled in send). On a 5xx the payload is persisted to the backfill
// bucket so it can be replayed later (best-effort; does not change the returned
// error).
func (client *DatadogClient) SendMessageToDatadog(ctx context.Context, message []byte, url string, extraHeaders ...map[string]string) error {
	ctx, cancel := context.WithTimeout(ctx, 3*time.Minute)
	defer cancel()
	status, err := client.send(ctx, message, url, extraHeaders...)
	if err != nil && status >= 500 && status < 600 {
		handleServerErrorPayload(ctx, message, url)
	}
	return err
}

// replaySend sends a payload read back from a backfill bucket. Unlike
// SendMessageToDatadog it never re-persists on a 5xx (the payload is already in
// the bucket), so a failed replay just returns its status and error and is left
// in place for the next run. The HTTP status lets the caller distinguish
// throttling (429) from other failures.
func (client *DatadogClient) replaySend(ctx context.Context, message []byte, url string, extraHeaders ...map[string]string) (int, error) {
	return client.send(ctx, message, url, extraHeaders...)
}

// send performs the HTTP send with a single 403 API-key-refresh retry. It does
// not persist on failure; callers decide what to do with the result.
func (client *DatadogClient) send(ctx context.Context, message []byte, url string, extraHeaders ...map[string]string) (int, error) {
	status, err := client.sendMessage(ctx, message, url, extraHeaders...)
	if err != nil && status == http.StatusForbidden {
		if refreshErr := client.refreshAPIKey(ctx); refreshErr != nil {
			return status, refreshErr
		}
		status, err = client.sendMessage(ctx, message, url, extraHeaders...)
	}
	return status, err
}

func (client *DatadogClient) sendMessage(ctx context.Context, message []byte, url string, extraHeaders ...map[string]string) (int, error) {
	apiHeaders := map[string]string{
		"Content-Encoding": "gzip",
		"Content-Type":     "application/json",
		"DD-API-KEY":       client.apiKey,
	}
	for _, h := range extraHeaders {
		for k, v := range h {
			apiHeaders[k] = v
		}
	}
	fmt.Printf("Uncompressed payload size=%.2fKB\n", float64(len(message))/1024.0)
	req, err := client.client.PrepareRequest(ctx, url, http.MethodPost, message, apiHeaders, nil, nil, nil)
	if err != nil {
		return http.StatusInternalServerError, err
	}

	resp, err := client.client.CallAPI(req)
	if err != nil {
		return http.StatusInternalServerError, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		log.Printf("Error: Received non-200 response from Datadog: %d", resp.StatusCode)
		body, err := datadog.ReadBody(resp)
		if err == nil {
			log.Printf("Error response body: %s", string(body))
		}
		return resp.StatusCode, errors.New("failed to send message to Datadog")
	}
	return resp.StatusCode, nil
}

func NewDatadogClient() (DatadogClient, error) {
	if cache != nil {
		return *cache, nil
	}
	secretOCID := os.Getenv("API_KEY_SECRET_OCID")
	homeRegion := os.Getenv("HOME_REGION")
	if secretOCID == "" || homeRegion == "" {
		return DatadogClient{}, errors.New("missing one of the required environment variables: API_KEY_SECRET_OCID, HOME_REGION")
	}

	configuration := datadog.NewConfiguration()
	configuration.RetryConfiguration.EnableRetry = true
	client := datadog.NewAPIClient(configuration)

	cache = &DatadogClient{
		client:      client,
		secretOCID:  secretOCID,
		vaultRegion: homeRegion,
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel() // releases resources if fetchAPIKeyFromVault completes before timeout elapses
	apiKey, err := cache.fetchAPIKeyFromVault(ctx)
	if err != nil {
		return DatadogClient{}, err
	}
	cache.apiKey = apiKey
	return *cache, nil
}

func NewDatadogClientWithSite() (DatadogClient, string, error) {
	site := os.Getenv("DD_SITE")
	if site == "" {
		return DatadogClient{}, "", errors.New("missing required environment variable DD_SITE")
	}
	client, err := NewDatadogClient()
	return client, site, err
}

func NewDatadogClientWithTenancyAndSite() (DatadogClient, string, string, error) {
	tenancyOCID := os.Getenv("TENANCY_OCID")
	if tenancyOCID == "" {
		return DatadogClient{}, "", "", errors.New("missing required environment variable TENANCY_OCID")
	}
	client, site, err := NewDatadogClientWithSite()
	return client, tenancyOCID, site, err
}

// handleServerErrorPayload persists a payload that Datadog rejected with a 5xx to
// a per-data-type backfill bucket so it can be replayed later. The bucket is
// expected to already exist (provisioned out-of-band); if it does not, or the
// data type cannot be determined, the payload is dropped (logged). This is
// best-effort and never changes the status/error returned to the caller.
var handleServerErrorPayload = func(ctx context.Context, message []byte, intakeURL string) {
	bucket, err := backfillBucketName(intakeURL)
	if err != nil {
		log.Printf("5xx payload dropped: %v", err)
		return
	}

	osClient, err := newObjectStorageClientFunc()
	if err != nil {
		log.Printf("5xx payload dropped: failed to create object storage client: %v", err)
		return
	}

	namespace, err := getNamespace(ctx, osClient)
	if err != nil {
		log.Printf("5xx payload dropped: failed to resolve object storage namespace: %v", err)
		return
	}

	if !bucketExists(ctx, osClient, namespace, bucket) {
		log.Printf("5xx payload dropped: backfill bucket %q does not exist", bucket)
		return
	}

	objectName := backfillObjectName()
	if err := putObject(ctx, osClient, namespace, bucket, objectName, message); err != nil {
		log.Printf("5xx payload dropped: failed to write object %q to bucket %q: %v", objectName, bucket, err)
		return
	}
	log.Printf("5xx payload persisted to bucket %q as object %q", bucket, objectName)
}

// backfillBucketName maps a Datadog intake URL to the backfill bucket for that
// data type, returning an error if the type cannot be determined.
func backfillBucketName(intakeURL string) (string, error) {
	switch {
	case strings.Contains(intakeURL, "ocimetrics"):
		return "dd-metrics-backfill", nil
	case strings.Contains(intakeURL, "cloudchanges"):
		return "dd-events-backfill", nil
	case strings.Contains(intakeURL, "logs"):
		return "dd-logs-backfill", nil
	default:
		return "", fmt.Errorf("unrecognized intake url %q", intakeURL)
	}
}

// objectStorageAPI is the subset of the OCI Object Storage client used to persist
// backfill payloads. *objectstorage.ObjectStorageClient satisfies it; tests inject
// a fake via newObjectStorageClientFunc.
type objectStorageAPI interface {
	GetNamespace(ctx context.Context, request objectstorage.GetNamespaceRequest) (objectstorage.GetNamespaceResponse, error)
	HeadBucket(ctx context.Context, request objectstorage.HeadBucketRequest) (objectstorage.HeadBucketResponse, error)
	PutObject(ctx context.Context, request objectstorage.PutObjectRequest) (objectstorage.PutObjectResponse, error)
	ListObjects(ctx context.Context, request objectstorage.ListObjectsRequest) (objectstorage.ListObjectsResponse, error)
	GetObject(ctx context.Context, request objectstorage.GetObjectRequest) (objectstorage.GetObjectResponse, error)
	DeleteObject(ctx context.Context, request objectstorage.DeleteObjectRequest) (objectstorage.DeleteObjectResponse, error)
}

// newObjectStorageClientFunc is a seam allowing tests to inject a fake client.
var newObjectStorageClientFunc = newObjectStorageClient

// newObjectStorageClient builds an Object Storage client using Resource Principal
// authentication, mirroring the pattern in vault.go. The client is explicitly
// pinned to the function's own region (taken from the resource principal) so that
// every bucket operation targets that region's Object Storage endpoint, and thus
// that region's bucket.
func newObjectStorageClient() (objectStorageAPI, error) {
	rp, err := auth.ResourcePrincipalConfigurationProvider()
	if err != nil {
		return nil, fmt.Errorf("failed to create resource principal provider: %w", err)
	}

	osClient, err := objectstorage.NewObjectStorageClientWithConfigurationProvider(rp)
	if err != nil {
		return nil, fmt.Errorf("failed to create object storage client: %w", err)
	}

	region, err := rp.Region()
	if err != nil {
		return nil, fmt.Errorf("failed to determine function region: %w", err)
	}
	osClient.SetRegion(region)

	retryPolicy := common.DefaultRetryPolicy()
	osClient.SetCustomClientConfiguration(common.CustomClientConfiguration{RetryPolicy: &retryPolicy})

	return &osClient, nil
}

// getNamespace returns the tenancy's Object Storage namespace.
func getNamespace(ctx context.Context, osClient objectStorageAPI) (string, error) {
	resp, err := osClient.GetNamespace(ctx, objectstorage.GetNamespaceRequest{})
	if err != nil {
		return "", err
	}
	if resp.Value == nil {
		return "", errors.New("object storage returned an empty namespace")
	}

	return *resp.Value, nil
}

// bucketExists reports whether the named bucket exists in the namespace. A
// non-nil HeadBucket error (e.g. 404) is treated as "does not exist".
func bucketExists(ctx context.Context, osClient objectStorageAPI, namespace, bucket string) bool {
	_, err := osClient.HeadBucket(ctx, objectstorage.HeadBucketRequest{
		NamespaceName: common.String(namespace),
		BucketName:    common.String(bucket),
	})
	return err == nil
}

// putObject writes the payload to the bucket under the given object name.
func putObject(ctx context.Context, osClient objectStorageAPI, namespace, bucket, objectName string, data []byte) error {
	_, err := osClient.PutObject(ctx, objectstorage.PutObjectRequest{
		NamespaceName: common.String(namespace),
		BucketName:    common.String(bucket),
		ObjectName:    common.String(objectName),
		ContentLength: common.Int64(int64(len(data))),
		PutObjectBody: io.NopCloser(bytes.NewReader(data)),
	})
	return err
}

// backfillObjectName builds a timestamped object key for a failed payload.
func backfillObjectName() string {
	return fmt.Sprintf("%s.json", time.Now().UTC().Format("20060102T150405.000000000"))
}

// throttleBackoff is how long to wait before retrying a replay that was throttled
// (429). It is a var so tests can set it to zero.
var throttleBackoff = 5 * time.Second

// backfillTrigger is the control message hubmanager sends to invoke backfill mode.
type backfillTrigger struct {
	BackfillMode string `json:"backfill_mode"`
}

// IsBackfillTrigger reports whether the invocation input is the backfill control
// message {"backfill_mode":"true"} rather than normal telemetry to forward.
func IsBackfillTrigger(raw []byte) bool {
	var t backfillTrigger
	return json.Unmarshal(raw, &t) == nil && t.BackfillMode == "true"
}

// BackfillSummary reports what a backfill run accomplished, so the outcome is
// visible in the function's response and not only in logs.
type BackfillSummary struct {
	Replayed       int // objects delivered to Datadog (whether or not the delete then succeeded)
	Skipped        int // objects that could not be read; left in place for the next run
	DeleteFailures int // objects delivered but not deleted; re-sent next run (at-least-once)
}

// String renders the summary for inclusion in the function response.
func (s BackfillSummary) String() string {
	return fmt.Sprintf("replayed=%d skipped=%d delete_failures=%d", s.Replayed, s.Skipped, s.DeleteFailures)
}

// Backfill drains this region's backfill bucket for the given intake URL, replaying
// each stored batch to Datadog and deleting it on success. It is invoked on a
// schedule (every ~5 min) and processes objects until the bucket is empty, an
// unrecoverable send failure occurs, or the function times out — all of which are
// safe interruption points, since any undelivered object is left for the next run.
// It returns a BackfillSummary of what happened; the summary is also returned on
// error, reflecting partial progress.
func (client *DatadogClient) Backfill(ctx context.Context, intakeURL string, extraHeaders ...map[string]string) (BackfillSummary, error) {
	var summary BackfillSummary

	bucket, err := backfillBucketName(intakeURL)
	if err != nil {
		return summary, err
	}

	osClient, err := newObjectStorageClientFunc()
	if err != nil {
		return summary, fmt.Errorf("backfill: failed to create object storage client: %w", err)
	}

	namespace, err := getNamespace(ctx, osClient)
	if err != nil {
		return summary, fmt.Errorf("backfill: failed to resolve object storage namespace: %w", err)
	}

	req := objectstorage.ListObjectsRequest{
		NamespaceName: common.String(namespace),
		BucketName:    common.String(bucket),
	}
	for {
		resp, err := osClient.ListObjects(ctx, req)
		if err != nil {
			return summary, fmt.Errorf("backfill: failed to list objects in bucket %q: %w", bucket, err)
		}

		for _, obj := range resp.Objects {
			if obj.Name == nil {
				continue
			}
			name := *obj.Name

			data, err := getObject(ctx, osClient, namespace, bucket, name)
			if err != nil {
				log.Printf("backfill: failed to read object %q, skipping: %v", name, err)
				summary.Skipped++
				continue
			}

			if err := client.replayWithRetry(ctx, data, intakeURL, extraHeaders...); err != nil {
				// Unrecoverable after one retry. Leave the object in place and stop
				// this run; hubmanager will invoke again shortly.
				return summary, fmt.Errorf("backfill: replay failed for object %q, stopping run: %w", name, err)
			}
			summary.Replayed++

			if err := deleteObject(ctx, osClient, namespace, bucket, name); err != nil {
				// Delivered but not deleted: it will be re-sent next run (at-least-once).
				log.Printf("backfill: delivered but failed to delete object %q: %v", name, err)
				summary.DeleteFailures++
			}
		}

		if resp.NextStartWith == nil || *resp.NextStartWith == "" {
			return summary, nil
		}
		req.Start = resp.NextStartWith
	}
}

// replayWithRetry sends a replayed payload, retrying once on failure. On a 429 it
// waits throttleBackoff before the retry. It returns an error only if the retry
// also fails.
func (client *DatadogClient) replayWithRetry(ctx context.Context, data []byte, intakeURL string, extraHeaders ...map[string]string) error {
	status, err := client.replaySend(ctx, data, intakeURL, extraHeaders...)
	if err == nil {
		return nil
	}

	if status == http.StatusTooManyRequests {
		select {
		case <-time.After(throttleBackoff):
		case <-ctx.Done():
			return ctx.Err()
		}
	}

	_, err = client.replaySend(ctx, data, intakeURL, extraHeaders...)
	return err
}

// getObject reads an object's contents from the bucket.
func getObject(ctx context.Context, osClient objectStorageAPI, namespace, bucket, objectName string) ([]byte, error) {
	resp, err := osClient.GetObject(ctx, objectstorage.GetObjectRequest{
		NamespaceName: common.String(namespace),
		BucketName:    common.String(bucket),
		ObjectName:    common.String(objectName),
	})
	if err != nil {
		return nil, err
	}
	defer resp.Content.Close()
	return io.ReadAll(resp.Content)
}

// deleteObject removes an object from the bucket.
func deleteObject(ctx context.Context, osClient objectStorageAPI, namespace, bucket, objectName string) error {
	_, err := osClient.DeleteObject(ctx, objectstorage.DeleteObjectRequest{
		NamespaceName: common.String(namespace),
		BucketName:    common.String(bucket),
		ObjectName:    common.String(objectName),
	})
	return err
}
