package client

import (
	"bytes"
	"context"
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

// SendMessageToDatadog sends a message to Datadog. If the initial attempt fails with a 403 status code,
// it tries to refresh the API key and resend the message.
//
// Parameters:
//
//	ctx - The context for the request.
//	message - The message to be sent as a byte slice.
//	url - The URL to which the message should be sent.
//
// Returns:
//
//	error - An error if the message could not be sent or if the API key could not be refreshed.
//
// SendMessageToDatadog sends a message to Datadog. extraHeaders are merged into
// the request headers and can be used to pass caller-specific metadata (e.g.
// "Dd-Oci-Tenancy-Id"). If the initial attempt fails with a 403, the API key
// is refreshed and the request is retried once.
func (client *DatadogClient) SendMessageToDatadog(ctx context.Context, message []byte, url string, extraHeaders ...map[string]string) error {
	ctx, cancel := context.WithTimeout(ctx, 3*time.Minute)
	defer cancel()
	status, err := client.sendMessage(ctx, message, url, extraHeaders...)
	if err != nil && status == http.StatusForbidden {
		err = client.refreshAPIKey(ctx)
		if err != nil {
			return err
		}
		_, err = client.sendMessage(ctx, message, url, extraHeaders...)
		return err
	}
	return err
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
		// On a 5xx the payload is undeliverable right now. Persist it to the
		// per-data-type backfill bucket if one exists so it can be replayed
		// later; otherwise drop it for now. This is best-effort and does not
		// change the status/error returned below.
		if resp.StatusCode >= 500 && resp.StatusCode < 600 {
			handleServerErrorPayload(ctx, message, url)
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
func handleServerErrorPayload(ctx context.Context, message []byte, intakeURL string) {
	bucket := backfillBucketName(intakeURL)
	if bucket == "" {
		log.Printf("5xx payload dropped: could not determine data type from url %q", intakeURL)
		return
	}

	osClient, err := newObjectStorageClient()
	if err != nil {
		log.Printf("5xx payload dropped: %v", err)
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
// data type, or "" if the type cannot be determined.
func backfillBucketName(intakeURL string) string {
	switch {
	case strings.Contains(intakeURL, "ocimetrics"):
		return "dd-metrics-backfill"
	case strings.Contains(intakeURL, "cloudchanges"):
		return "dd-events-backfill"
	case strings.Contains(intakeURL, "logs"):
		return "dd-logs-backfill"
	default:
		return ""
	}
}

// newObjectStorageClient builds an Object Storage client using Resource Principal
// authentication, mirroring the pattern in vault.go. The client is explicitly
// pinned to the function's own region (taken from the resource principal) so that
// every bucket operation targets that region's Object Storage endpoint, and thus
// that region's bucket.
func newObjectStorageClient() (*objectstorage.ObjectStorageClient, error) {
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
func getNamespace(ctx context.Context, osClient *objectstorage.ObjectStorageClient) (string, error) {
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
func bucketExists(ctx context.Context, osClient *objectstorage.ObjectStorageClient, namespace, bucket string) bool {
	_, err := osClient.HeadBucket(ctx, objectstorage.HeadBucketRequest{
		NamespaceName: common.String(namespace),
		BucketName:    common.String(bucket),
	})
	return err == nil
}

// putObject writes the payload to the bucket under the given object name.
func putObject(ctx context.Context, osClient *objectstorage.ObjectStorageClient, namespace, bucket, objectName string, data []byte) error {
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
