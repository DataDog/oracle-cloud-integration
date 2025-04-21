package client

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"

	"github.com/oracle/oci-go-sdk/v65/common"
	"github.com/oracle/oci-go-sdk/v65/common/auth"
	"github.com/oracle/oci-go-sdk/v65/secrets"
)

func (client *DatadogClient) refreshAPIKey(ctx context.Context) error {
	apiKey, err := client.fetchAPIKeyFromVault(ctx)
	if err != nil {
		return err
	}
	client.apiKey = apiKey
	return nil
}

// fetchAPIKeyFromVault retrieves the Datadog API Key stored in OCI Vault.
func (client *DatadogClient) fetchAPIKeyFromVault(ctx context.Context) (string, error) {
	// Create a resource principal authentication provider
	rp, err := auth.ResourcePrincipalConfigurationProvider()
	if err != nil {
		return "", fmt.Errorf("failed to create resource principal provider: %v", err)
	}

	// Create a SecretsClient using the RP provider
	secretsClient, err := secrets.NewSecretsClientWithConfigurationProvider(rp)
	if err != nil {
		return "", fmt.Errorf("failed to create secrets client: %v", err)
	}
	//Set retry policy
	retryPolicy := common.DefaultRetryPolicy()
	secretsClient.SetCustomClientConfiguration(common.CustomClientConfiguration{
		RetryPolicy: &retryPolicy,
	})
	secretsClient.SetRegion(client.vaultRegion)

	// Fetch the secret
	request := secrets.GetSecretBundleRequest{
		SecretId: &client.secretOCID,
	}

	response, err := secretsClient.GetSecretBundle(ctx, request)
	if err != nil {
		return "", fmt.Errorf("failed to fetch secret: %v", err)
	}

	// Extract and decode the secret
	base64Content, ok := response.SecretBundleContent.(secrets.Base64SecretBundleContentDetails)
	if !ok || base64Content.Content == nil {
		return "", errors.New("secret content is nil")
	}

	decodedSecret, err := base64.StdEncoding.DecodeString(*base64Content.Content)
	if err != nil {
		return "", fmt.Errorf("failed to decode secret: %v", err)
	}

	return string(decodedSecret), nil
}
