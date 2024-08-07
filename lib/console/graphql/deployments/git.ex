defmodule Console.GraphQl.Deployments.Git do
  use Console.GraphQl.Schema.Base
  alias Console.GraphQl.Resolvers.Deployments
  alias Console.Schema.{GitRepository, PullRequest, ScmConnection, ScmWebhook, PrAutomation, Configuration}

  ecto_enum :auth_method, GitRepository.AuthMethod
  ecto_enum :git_health, GitRepository.Health
  ecto_enum :scm_type, ScmConnection.Type
  ecto_enum :match_strategy, PrAutomation.MatchStrategy
  ecto_enum :pr_role, PrAutomation.Role
  ecto_enum :pr_status, PullRequest.Status
  ecto_enum :configuration_type, Configuration.Type
  ecto_enum :operation, Configuration.Condition.Operation

  input_object :git_attributes do
    field :url,           non_null(:string), description: "the url of this repository"
    field :private_key,   :string, description: "an ssh private key to use with this repo if an ssh url was given"
    field :passphrase,    :string, description: "a passphrase to decrypt the given private key"
    field :username,      :string, description: "the http username for authenticated http repos, defaults to apiKey for github"
    field :password,      :string, description: "the http password for http authenticated repos"
    field :https_path,    :string, description: "a manually supplied https path for non standard git setups.  This is auto-inferred in many cases"
    field :url_format,    :string, description: "similar to https_path, a manually supplied url format for custom git.  Should be something like {url}/tree/{ref}/{folder}"
    field :connection_id, :id, description: "id of a scm connection to use for authentication"
    field :decrypt,       :boolean, description: "whether to run plural crypto on this repo"
  end

  @desc "an object representing a means to authenticate to a source control provider like Github"
  input_object :scm_connection_attributes do
    field :name,                non_null(:string)
    field :type,                non_null(:scm_type)
    field :owner,               :string, description: "the owning entity in this scm provider, eg a github organization"
    field :username,            :string
    field :token,               :string
    field :base_url,            :string
    field :api_url,             :string
    field :github,              :github_app_attributes
    field :signing_private_key, :string, description: "a ssh private key to be used for commit signing"
  end

  @desc "Requirements to perform Github App authentication"
  input_object :github_app_attributes do
    field :app_id,          non_null(:string), description: "Github App ID"
    field :installation_id, non_null(:string), description: "ID of this github app installation"
    field :private_key,     non_null(:string), description: "PEM-encoded private key for this app"
  end

  @desc "A way to create a self-service means of generating PRs against an IaC repo"
  input_object :pr_automation_attributes do
    field :name,          :string
    field :role,          :pr_role
    field :identifier,    :string, description: "string id for a repository, eg for github, this is {organization}/{repository-name}"
    field :documentation, :string
    field :title,         :string
    field :message,       :string
    field :branch,        :string
    field :updates,       :pr_automation_update_spec_attributes
    field :creates,       :pr_automation_create_spec_attributes
    field :deletes,       :pr_automation_delete_spec_attributes

    field :addon,         :string, description: "link to an add-on name if this can update it"
    field :cluster_id,    :id, description: "link to a cluster if this is to perform an upgrade"
    field :service_id,    :id, description: "link to a service if this can modify its configuration"
    field :connection_id, :id, description: "the scm connection to use for pr generation"

    field :repository_id, :id, description: "a git repository to use for create mode prs"

    field :configuration, list_of(:pr_configuration_attributes)

    field :write_bindings,  list_of(:policy_binding_attributes), description: "users who can update this automation"
    field :create_bindings, list_of(:policy_binding_attributes), description: "users who can create prs with this automation"
  end

  @desc "the a configuration item for creating a new pr"
  input_object :pr_configuration_attributes do
    field :type,          non_null(:configuration_type)
    field :name,          non_null(:string)
    field :default,       :string
    field :documentation, :string
    field :longform,      :string
    field :placeholder,   :string
    field :optional,      :boolean
    field :condition,     :condition_attributes
    field :values,        list_of(:string)
  end

  @desc "attributes for declaratively specifying whether a config item is relevant given prior config"
  input_object :condition_attributes do
    field :operation, non_null(:operation)
    field :field,     non_null(:string)
    field :value,     :string
  end

  @desc "The operations to be performed on the files w/in the pr"
  input_object :pr_automation_update_spec_attributes do
    field :regexes,            list_of(:string)
    field :regex_replacements, list_of(:regex_replacement_attributes),
      description: "list of regex scope replacement templates, useful for ANY strategies"
    field :files,              list_of(:string)
    field :replace_template,   :string
    field :yq,                 :string
    field :match_strategy,     :match_strategy
  end

  @desc "Operations to create new templated files within this pr"
  input_object :pr_automation_create_spec_attributes do
    field :git,       :git_ref_attributes
    field :templates, list_of(:pr_automation_template_attributes)
  end

  @desc "Operations to delete files within this pr"
  input_object :pr_automation_delete_spec_attributes do
    field :files,     list_of(non_null(:string))
    field :folders,   list_of(non_null(:string))
  end

  @desc "a fully specify regex/replace flow"
  input_object :regex_replacement_attributes do
    field :regex,       non_null(:string)
    field :replacement, non_null(:string)
    field :file,        non_null(:string), description: "the filename to apply this regex on"
    field :templated,   :boolean,
      description: "whether you want to apply liquid templating on the regex before compiling"
  end

  @desc "templates to apply in this pr"
  input_object :pr_automation_template_attributes do
    field :source,      non_null(:string)
    field :destination, non_null(:string)
    field :external,    non_null(:boolean),
      description: "whether the source template is sourced from an external git repo bound to this automation"
  end

  @desc "attributes for a pull request pointer record"
  input_object :pull_request_attributes do
    field :url,        non_null(:string)
    field :title,      non_null(:string)
    field :creator,    :string
    field :labels,     list_of(:string)
    field :service_id, :id
    field :cluster_id, :id
    field :service,    :namespaced_name
    field :cluster,    :namespaced_name
  end

  @desc "attributes for a pull request pointer record"
  input_object :pull_request_update_attributes do
    field :title,      non_null(:string)
    field :labels,     list_of(:string)
    field :status,     non_null(:pr_status)
    field :service_id, :id
    field :cluster_id, :id
    field :service,    :namespaced_name
    field :cluster,    :namespaced_name
  end

  @desc "The attributes to configure a new webhook for a SCM provider"
  input_object :scm_webhook_attributes do
    field :hmac,  non_null(:string), description: "the secret token for authenticating this webhook via hmac signature"
    field :type,  non_null(:scm_type), description: "the type of webhook to create"
    field :owner, non_null(:string), description: "the owner for this webhook in your SCM, eg a github org or gitlab group"
  end

  @desc "a git repository available for deployments"
  object :git_repository do
    field :id,           non_null(:id), description: "internal id of this repository"
    field :url,          non_null(:string), description: "the git url of the repository, either https or ssh supported"
    field :auth_method,  :auth_method, description: "whether its a http or ssh url"
    field :health,       :git_health, description: "whether we can currently pull this repo with the provided credentials"
    field :pulled_at,    :datetime, description: "the last successsful git pull timestamp"
    field :error,        :string, description: "the error message if there were any pull errors"
    field :https_path,   :string, description: "the https url for this git repo"
    field :url_format,   :string, description: "a format string to get the http url for a subfolder in a git repo"
    field :decrypt,      :boolean, description: "whether to run plural crypto unlock on this repo"

    field :refs, list_of(non_null(:string)), description: "named refs like branches/tags for a repository", resolve: fn
      git, _, _ -> Deployments.git_refs(git)
    end

    field :editable, :boolean,
      resolve: &Deployments.editable/3,
      description: "whether the current user can edit this repo"

    timestamps()
  end

  @desc "a crd representation of a helm repository"
  object :helm_repository do
    field :metadata, non_null(:metadata)
    field :spec,     non_null(:helm_repository_spec)
    field :charts,   list_of(:helm_chart_entry),
      resolve: &Deployments.helm_charts/3,
      description: "the charts found in this repository (heavy operation, don't do in list endpoints)"
    field :status,   :helm_repository_status,
      resolve: &Deployments.helm_status/3,
      description: "can fetch the status of a given helm repository"
  end

  @desc "a specification of how a helm repository is fetched"
  object :helm_repository_spec do
    field :provider, :string
    field :url,      non_null(:string)
    field :type,     :string
  end

  @desc "the state of this helm repository"
  object :helm_repository_status do
    field :ready,   :boolean
    field :message, :string
  end

  @desc "a chart manifest entry, including all versions"
  object :helm_chart_entry do
    field :name,     :string, description: "the name of the chart"
    field :versions, list_of(:helm_chart_version), description: "all found versions of the chart"
  end

  @desc "a chart version contained within a helm repository manifest"
  object :helm_chart_version do
    field :app_version, :string, description: "the version of the app contained w/in this chart"
    field :version,     :string, description: "the version of the chart itself"
    field :name,        :string, description: "the name of the chart"
    field :type,        :string
    field :digest,      :string, description: "sha digest of this chart's contents"
  end

  @desc "an object representing the means to connect to SCM apis"
  object :scm_connection do
    field :id,       non_null(:id)
    field :name,     non_null(:string)
    field :type,     non_null(:scm_type)
    field :username, :string
    field :base_url, :string, description: "base url for git clones for self-hosted versions"
    field :api_url,  :string, description: "base url for HTTP apis for self-hosted versions if different from base url"

    timestamps()
  end

  @desc "a description of how to generate a pr, which can either modify existing files or generate new ones w/in a repo"
  object :pr_automation do
    field :id,            non_null(:id)
    field :identifier,    non_null(:string), description: "string id for a repository, eg for github, this is {organization}/{repository-name}"
    field :name,          non_null(:string), description: "the name for this automation"
    field :role,          :pr_role, description: "An enum describing the high-level responsibility of this pr, eg creating a cluster or service, or upgrading a cluster"
    field :documentation, :string
    field :title,         non_null(:string)
    field :message,       non_null(:string)
    field :updates,       :pr_update_spec
    field :creates,       :pr_create_spec
    field :deletes,       :pr_delete_spec

    field :configuration, list_of(:pr_configuration)

    field :write_bindings, list_of(:policy_binding),
      description: "write policy for this pr automation, also propagates to the notifications list for any created PRs",
      resolve: dataloader(Deployments)

    field :create_bindings, list_of(:policy_binding),
      description: "users who can generate prs with this automation",
      resolve: dataloader(Deployments)

    field :addon,      :string, description: "link to an add-on name if this can update it"
    field :repository, :git_repository,
      description: "the git repository to use for sourcing external templates",
      resolve: dataloader(Deployments)
    field :cluster,    :cluster,
      description: "link to a cluster if this is to perform an upgrade",
      resolve: dataloader(Deployments)
    field :service,    :service_deployment,
      description: "link to a service if this can update its configuration",
      resolve: dataloader(Deployments)
    field :connection, :scm_connection,
      description: "the scm connection to use for pr generation",
      resolve: dataloader(Deployments)

    timestamps()
  end

  @desc "existing file updates that can be performed in a PR"
  object :pr_update_spec do
    field :regexes,            list_of(:string)
    field :regex_replacements, list_of(:regex_replacement)
    field :files,              list_of(:string)
    field :replace_template,   :string
    field :yq,                 :string
    field :match_strategy,     :match_strategy
  end

  @desc "templated files used to add new files to a given pr"
  object :pr_create_spec do
    field :git, :git_ref, description: "pointer within an external git repository to source templates from"
    field :templates, list_of(:pr_template_spec)
  end

  @desc "Files or folders you want to delete in this pr"
  object :pr_delete_spec do
    field :files,     list_of(non_null(:string))
    field :folders,   list_of(non_null(:string))
  end

  @desc "the details of where to find and place a templated file"
  object :pr_template_spec do
    field :source,      non_null(:string)
    field :destination, non_null(:string)
    field :external,    non_null(:boolean)
  end

  @desc "a fully specified regex/replace flow"
  object :regex_replacement do
    field :regex,       non_null(:string)
    field :file,        non_null(:string), description: "the file to apply this replacement on"
    field :replacement, non_null(:string), description: "template string to replace any match with"
    field :templated,   :boolean, description: "Whether to apply liquid templating before compiling this regex"
  end

  @desc "the a configuration item for creating a new pr, used for templating the ultimate code changes made"
  object :pr_configuration do
    field :type,          non_null(:configuration_type)
    field :name,          non_null(:string)
    field :default,       :string
    field :documentation, :string
    field :longform,      :string
    field :placeholder,   :string
    field :optional,      :boolean
    field :values,        list_of(:string)
    field :condition,     :pr_configuration_condition
  end

  @desc "declaritive spec for whether a config item is relevant given prior config"
  object :pr_configuration_condition do
    field :operation, non_null(:operation), description: "a boolean operation to apply"
    field :field,     non_null(:string), description: "the prior field to check"
    field :value,     :string, description: "a fixed value to check against if its a binary operation"
  end

  @desc "A reference to a pull request for your kubernetes related IaC"
  object :pull_request do
    field :id,      non_null(:id)
    field :status,  :pr_status
    field :url,     non_null(:string)
    field :title,   :string
    field :creator, :string
    field :labels,  list_of(:string)

    field :cluster, :cluster, description: "the cluster this pr is meant to modify",
      resolve: dataloader(Deployments)
    field :service, :service_deployment, description: "the service this pr is meant to modify",
      resolve: dataloader(Deployments)

    timestamps()
  end

  object :scm_webhook do
    field :id,    non_null(:id)
    field :type,  non_null(:scm_type)
    field :owner, non_null(:string)

    field :url, non_null(:string),
      description: "the url for this specific webhook",
      resolve: fn hook, _, _ -> {:ok, ScmWebhook.url(hook)} end

    field :name,  non_null(:string),
      description: "the name in your SCM provider for this webhook",
      resolve: fn hook, _, _ -> {:ok, ScmWebhook.name(hook)} end

    timestamps()
  end

  @desc "A representation to a service which configures renovate for a scm connection"
  object :dependency_management_service do
    field :id, non_null(:id)
    field :connection, :scm_connection, resolve: dataloader(Deployments)
    field :service, :service_deployment, resolve: dataloader(Deployments)

    timestamps()
  end

  connection node_type: :git_repository
  connection node_type: :scm_connection
  connection node_type: :pr_automation
  connection node_type: :pull_request
  connection node_type: :scm_webhook
  connection node_type: :dependency_management_service

  delta :git_repository

  object :git_queries do
    field :git_repository, :git_repository do
      middleware Authenticated
      arg :id,  :id
      arg :url, :string

      resolve &Deployments.resolve_git/2
    end

    connection field :git_repositories, node_type: :git_repository do
      middleware Authenticated

      resolve &Deployments.list_git_repositories/2
    end

    field :helm_repositories, list_of(:helm_repository) do
      middleware Authenticated

      resolve &Deployments.list_helm_repositories/2
    end

    field :helm_repository, :helm_repository do
      middleware Authenticated
      arg :name,      non_null(:string)
      arg :namespace, non_null(:string)

      resolve &Deployments.get_helm_repository/2
    end

    connection field :scm_connections, node_type: :scm_connection do
      middleware Authenticated

      resolve &Deployments.list_scm_connections/2
    end

    field :scm_connection, :scm_connection do
      middleware Authenticated
      arg :id,   :id
      arg :name, :string

      resolve &Deployments.resolve_scm_connection/2
    end

    connection field :pr_automations, node_type: :pr_automation do
      middleware Authenticated

      resolve &Deployments.list_pr_automations/2
    end

    field :pr_automation, :pr_automation do
      middleware Authenticated
      arg :id,   :id
      arg :name, :string

      resolve &Deployments.resolve_pr_automation/2
    end

    connection field :pull_requests, node_type: :pull_request do
      middleware Authenticated
      arg :cluster_id, :id
      arg :service_id, :id
      arg :open,       :boolean
      arg :q,          :string

      resolve &Deployments.list_pull_requests/2
    end

    connection field :scm_webhooks, node_type: :scm_webhook do
      middleware Authenticated

      resolve &Deployments.list_scm_webhooks/2
    end

    connection field :dependency_management_services, node_type: :dependency_management_service do
      middleware Authenticated

      resolve &Deployments.list_dependency_management_services/2
    end
  end

  object :git_mutations do
    field :create_git_repository, :git_repository do
      middleware Authenticated
      arg :attributes, non_null(:git_attributes)

      safe_resolve &Deployments.create_git_repository/2
    end

    field :update_git_repository, :git_repository do
      middleware Authenticated
      arg :id,         non_null(:id)
      arg :attributes, non_null(:git_attributes)

      safe_resolve &Deployments.update_git_repository/2
    end

    field :delete_git_repository, :git_repository do
      middleware Authenticated
      arg :id, non_null(:id)

      safe_resolve &Deployments.delete_git_repository/2
    end

    field :create_scm_connection, :scm_connection do
      middleware Authenticated
      arg :attributes, non_null(:scm_connection_attributes)

      safe_resolve &Deployments.create_scm_connection/2
    end

    field :update_scm_connection, :scm_connection do
      middleware Authenticated
      arg :id,         non_null(:id)
      arg :attributes, non_null(:scm_connection_attributes)

      safe_resolve &Deployments.update_scm_connection/2
    end

    field :delete_scm_connection, :scm_connection do
      middleware Authenticated
      arg :id, non_null(:id)

      safe_resolve &Deployments.delete_scm_connection/2
    end

    field :create_scm_webhook, :scm_webhook do
      middleware Authenticated
      arg :connection_id, non_null(:id)
      arg :owner,         non_null(:string)

      safe_resolve &Deployments.create_webhook_for_connection/2
    end

    @desc "creates a webhook reference in our system but doesn't attempt to create it in your upstream provider"
    field :create_scm_webhook_pointer, :scm_webhook do
      middleware Authenticated
      arg :attributes, non_null(:scm_webhook_attributes)

      resolve &Deployments.create_webhook/2
    end

    field :create_pr_automation, :pr_automation do
      middleware Authenticated
      arg :attributes, non_null(:pr_automation_attributes)

      safe_resolve &Deployments.create_pr_automation/2
    end

    field :update_pr_automation, :pr_automation do
      middleware Authenticated
      arg :id,         non_null(:id)
      arg :attributes, non_null(:pr_automation_attributes)

      safe_resolve &Deployments.update_pr_automation/2
    end

    field :delete_pr_automation, :pr_automation do
      middleware Authenticated
      arg :id, non_null(:id)

      safe_resolve &Deployments.delete_pr_automation/2
    end

    @desc "creates the service to enable self-hosted renovate in one pass"
    field :setup_renovate, :service_deployment do
      middleware Authenticated
      arg :connection_id, non_null(:id)
      arg :repos,         list_of(:string)
      arg :name,          :string, description: "the name of the owning service"
      arg :namespace,     :string, description: "the namespace of the owning service"

      safe_resolve &Deployments.setup_renovate/2
    end

    field :reconfigure_renovate, :service_deployment do
      middleware Authenticated
      arg :repos,      list_of(:string)
      arg :service_id, non_null(:id)

      safe_resolve &Deployments.reconfigure_renovate/2
    end

    field :create_pull_request, :pull_request do
      middleware Authenticated
      arg :id,         non_null(:id), description: "the id of the PR automation instance to use"
      arg :identifier, :string
      arg :branch,     :string
      arg :context,    :json

      safe_resolve &Deployments.create_pull_request/2
    end

    @desc "just registers a pointer record to a PR after it was created externally be some other automation"
    field :create_pull_request_pointer, :pull_request do
      middleware Authenticated
      middleware Scope, api: "createPullRequestPointer"
      arg :attributes, :pull_request_attributes

      safe_resolve &Deployments.create_pr/2
    end

    field :update_pull_request, :pull_request do
      middleware Authenticated
      arg :id,         non_null(:id)
      arg :attributes, :pull_request_update_attributes

      safe_resolve &Deployments.update_pr/2
    end

    field :delete_pull_request, :pull_request do
      middleware Authenticated
      arg :id, non_null(:id)

      safe_resolve &Deployments.delete_pr/2
    end
  end
end
