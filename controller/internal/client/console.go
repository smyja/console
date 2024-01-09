package client

import (
	"context"
	"net/http"

	gqlgenclient "github.com/Yamashou/gqlgenc/client"

	console "github.com/pluralsh/console-client-go"

	"github.com/pluralsh/console/controller/api/v1alpha1"
)

type authedTransport struct {
	token   string
	wrapped http.RoundTripper
}

func (t *authedTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	req.Header.Set("Authorization", "Token "+t.token)
	return t.wrapped.RoundTrip(req)
}

type client struct {
	ctx           context.Context
	consoleClient *console.Client
}

type ConsoleClient interface {
	GetServices() ([]*console.ServiceDeploymentBaseFragment, error)
	GetService(clusterID, serviceName string) (*console.ServiceDeploymentExtended, error)
	UpdateComponents(id string, components []*console.ComponentAttributes, errs []*console.ServiceErrorAttributes) error
	CreateRepository(url string, privateKey, passphrase, username, password *string) (*console.CreateGitRepository, error)
	ListRepositories() (*console.ListGitRepositories, error)
	UpdateRepository(id string, attrs console.GitAttributes) (*console.UpdateGitRepository, error)
	DeleteRepository(id string) error
	GetRepository(url *string) (*console.GetGitRepository, error)
	CreateService(clusterId *string, attributes console.ServiceDeploymentAttributes) (*console.ServiceDeploymentFragment, error)
	GetCluster(id *string) (*console.ClusterFragment, error)
	GetClusterByHandle(handle *string) (*console.ClusterFragment, error)
	CreateCluster(attrs console.ClusterAttributes) (*console.ClusterFragment, error)
	UpdateCluster(id string, attrs console.ClusterUpdateAttributes) (*console.ClusterFragment, error)
	ListClusters() (*console.ListClusters, error)
	DeleteCluster(id string) (*console.ClusterFragment, error)
	IsClusterExisting(id *string) bool
	IsClusterDeleting(id *string) bool
	CreateProvider(ctx context.Context, attributes console.ClusterProviderAttributes, options ...gqlgenclient.HTTPRequestOption) (*console.ClusterProviderFragment, error)
	GetProvider(ctx context.Context, id string, options ...gqlgenclient.HTTPRequestOption) (*console.ClusterProviderFragment, error)
	GetProviderByCloud(ctx context.Context, cloud v1alpha1.CloudProvider, options ...gqlgenclient.HTTPRequestOption) (*console.ClusterProviderFragment, error)
	UpdateProvider(ctx context.Context, id string, attributes console.ClusterProviderUpdateAttributes, options ...gqlgenclient.HTTPRequestOption) (*console.ClusterProviderFragment, error)
	DeleteProvider(ctx context.Context, id string, options ...gqlgenclient.HTTPRequestOption) error
	IsProviderExists(ctx context.Context, id string) bool
	IsProviderDeleting(ctx context.Context, id string) bool
	UpdateService(serviceId string, attributes console.ServiceUpdateAttributes) error
	DeleteService(serviceId string) error
}

func New(url, token string) ConsoleClient {
	httpClient := http.Client{
		Transport: &authedTransport{
			token:   token,
			wrapped: http.DefaultTransport,
		},
	}

	return &client{
		consoleClient: console.NewClient(&httpClient, url),
		ctx:           context.Background(),
	}
}