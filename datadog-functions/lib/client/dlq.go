package client

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"io"
	"time"

	"github.com/oracle/oci-go-sdk/v65/common"
	"github.com/oracle/oci-go-sdk/v65/common/auth"
	"github.com/oracle/oci-go-sdk/v65/objectstorage"
)

// DLQClient writes and reads payloads from an OCI Object Storage bucket (dead-letter queue).
type DLQClient struct {
	namespace string
	bucket    string
	region    string
	client    objectstorage.ObjectStorageClient
}

// NewDLQClient creates a DLQ client from the given namespace, bucket name, and region.
// Pass the parameters from the request (e.g. headers or replay body). If any is empty,
// returns (nil, nil) so callers can skip DLQ when not configured.
func NewDLQClient(namespace, bucketName, region string) (*DLQClient, error) {
	if namespace == "" || bucketName == "" || region == "" {
		return nil, nil
	}

	rp, err := auth.ResourcePrincipalConfigurationProvider()
	if err != nil {
		return nil, fmt.Errorf("dlq: resource principal: %w", err)
	}
	osc, err := objectstorage.NewObjectStorageClientWithConfigurationProvider(rp)
	if err != nil {
		return nil, fmt.Errorf("dlq: create client: %w", err)
	}
	osc.SetRegion(region)
	retry := common.DefaultRetryPolicy()
	osc.SetCustomClientConfiguration(common.CustomClientConfiguration{RetryPolicy: &retry})

	return &DLQClient{namespace: namespace, bucket: bucketName, region: region, client: osc}, nil
}

// Write stores payload in the bucket under key. Key should be unique (e.g. prefix/timestamp-uuid).
func (c *DLQClient) Write(ctx context.Context, key string, payload []byte) error {
	body := io.NopCloser(bytes.NewReader(payload))
	length := int64(len(payload))
	req := objectstorage.PutObjectRequest{
		NamespaceName: &c.namespace,
		BucketName:    &c.bucket,
		ObjectName:    &key,
		PutObjectBody: body,
		ContentLength: &length,
	}
	_, err := c.client.PutObject(ctx, req)
	return err
}

// WriteWithGeneratedKey stores payload under a key like "prefix/2006-01-02T15-04-05.000Z-<rand>.json".
// Returns the object key used.
func (c *DLQClient) WriteWithGeneratedKey(ctx context.Context, prefix string, payload []byte) (string, error) {
	var b [8]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", err
	}
	key := fmt.Sprintf("%s/%s-%s.json", prefix, time.Now().UTC().Format(time.RFC3339Nano), hex.EncodeToString(b[:]))
	if err := c.Write(ctx, key, payload); err != nil {
		return "", err
	}
	return key, nil
}

const defaultListKeysPageLimit = 500

// ListKeysPage returns one page of object names under the given prefix.
// start is the pagination cursor (nil for first page). nextStart is the cursor for the next page (nil when done).
// limit is the max keys per page; if <= 0, defaultListKeysPageLimit is used.
// Callers should process (e.g. read, send, delete) each key and then call again with start = nextStart until nextStart is nil.
func (c *DLQClient) ListKeysPage(ctx context.Context, prefix string, start *string, limit int) (keys []string, nextStart *string, err error) {
	if limit <= 0 {
		limit = defaultListKeysPageLimit
	}
	req := objectstorage.ListObjectsRequest{
		NamespaceName: &c.namespace,
		BucketName:    &c.bucket,
		Prefix:        &prefix,
		Start:         start,
		Limit:         &limit,
	}
	resp, err := c.client.ListObjects(ctx, req)
	if err != nil {
		return nil, nil, err
	}
	for _, o := range resp.Objects {
		if o.Name != nil {
			keys = append(keys, *o.Name)
		}
	}
	return keys, resp.NextStartWith, nil
}

// Read returns the full content of the object at key.
func (c *DLQClient) Read(ctx context.Context, key string) ([]byte, error) {
	req := objectstorage.GetObjectRequest{
		NamespaceName: &c.namespace,
		BucketName:    &c.bucket,
		ObjectName:    &key,
	}
	resp, err := c.client.GetObject(ctx, req)
	if err != nil {
		return nil, err
	}
	defer func() { _ = resp.Content.Close() }()
	return io.ReadAll(resp.Content)
}

// Delete removes the object at key from the bucket. Use after successful replay so the same payload is not replayed again.
func (c *DLQClient) Delete(ctx context.Context, key string) error {
	req := objectstorage.DeleteObjectRequest{
		NamespaceName: &c.namespace,
		BucketName:    &c.bucket,
		ObjectName:    &key,
	}
	_, err := c.client.DeleteObject(ctx, req)
	return err
}
