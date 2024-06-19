import { Link } from 'react-router-dom'
import {
  ServiceDeploymentDetailsFragment,
  ServiceDeploymentStatus,
  ServicePromotion,
  useKickServiceMutation,
} from 'generated/graphql'
import { CD_REL_PATH, CLUSTERS_REL_PATH } from 'routes/cdRoutesConsts'
import { InlineLink } from 'components/utils/typography/InlineLink'
import { useMemo } from 'react'
import {
  AppIcon,
  Chip,
  DryRunIcon,
  ErrorIcon,
  GitHubLogoIcon,
  Sidecar,
  SidecarItem,
} from '@pluralsh/design-system'
import { useTheme } from 'styled-components'

import { getProviderIconUrl } from 'components/utils/Provider'

import KickButton from 'components/utils/KickButton'

import { ServiceStatusChip } from '../ServiceStatusChip'

import { countDeprecations } from './deprecationUtils'
import ServicePromote from './ServicePromote'

export function ServiceDetailsSidecar({
  serviceDeployment,
}: {
  serviceDeployment?: ServiceDeploymentDetailsFragment | null | undefined
}) {
  const theme = useTheme()
  const deprecationCount = useMemo(() => {
    const { components } = serviceDeployment || {}

    return components ? countDeprecations(components) : 0
  }, [serviceDeployment])

  if (!serviceDeployment) {
    return null
  }
  const {
    id,
    name,
    status,
    cluster,
    git,
    helm,
    namespace,
    repository,
    helmRepository,
  } = serviceDeployment

  return (
    <div
      css={{
        display: 'flex',
        flexDirection: 'column',
        gap: theme.spacing.small,
      }}
    >
      <div
        style={{
          display: 'flex',
          flexDirection: 'column',
          gap: theme.spacing.small,
        }}
      >
        {status === ServiceDeploymentStatus.Paused &&
          serviceDeployment.promotion === ServicePromotion.Ignore && (
            <ServicePromote id={id} />
          )}
        <KickButton
          secondary
          pulledAt={repository?.pulledAt}
          kickMutationHook={useKickServiceMutation}
          message="Resync service"
          tooltipMessage="Use this to sync this service now instead of at the next poll interval"
          variables={{ id }}
        />
      </div>
      <Sidecar>
        {name && <SidecarItem heading="Service name"> {name}</SidecarItem>}
        {namespace && (
          <SidecarItem heading="Service namespace"> {namespace}</SidecarItem>
        )}
        <SidecarItem heading="Status">
          <div
            css={{
              display: 'flex',
              flexWrap: 'wrap',
              gap: theme.spacing.xsmall,
              alignItems: 'center',
            }}
          >
            <ServiceStatusChip status={status} />
            {!!serviceDeployment.dryRun && (
              <Chip severity="success">
                <DryRunIcon size={12} />
                Dry run
              </Chip>
            )}
          </div>
        </SidecarItem>
        <SidecarItem heading="Warnings">
          {deprecationCount > 0 ? (
            <Chip
              icon={<ErrorIcon />}
              severity="danger"
            >
              Deprecations
            </Chip>
          ) : (
            <Chip severity="success">None</Chip>
          )}
        </SidecarItem>
        {helmRepository && (
          <SidecarItem heading="Helm Repository">
            <div
              css={{
                display: 'flex',
                alignItems: 'center',
                gap: theme.spacing.xsmall,
              }}
            >
              <AppIcon
                spacing="padding"
                size="xxsmall"
                icon={helm ? undefined : <GitHubLogoIcon />}
                url={helm ? getProviderIconUrl('byok', theme.mode) : undefined}
              />
              {helmRepository.spec.url}
            </div>
          </SidecarItem>
        )}
        {helm && <SidecarItem heading="Helm Chart">{helm.chart}</SidecarItem>}
        {helm && (
          <SidecarItem
            heading="Chart Version"
            css={{
              wordBreak: 'break-word',
            }}
          >
            {helm.version}
          </SidecarItem>
        )}
        {repository && (
          <SidecarItem heading="Git repository">
            <div
              css={{
                display: 'flex',
                alignItems: 'center',
                gap: theme.spacing.xsmall,
              }}
            >
              <AppIcon
                spacing="padding"
                size="xxsmall"
                icon={<GitHubLogoIcon />}
              />
              {repository.url}
            </div>
          </SidecarItem>
        )}
        {git && <SidecarItem heading="Git folder">{git.folder}</SidecarItem>}
        {git && (
          <SidecarItem
            heading="Git ref"
            css={{
              wordBreak: 'break-word',
            }}
          >
            {git.ref}
          </SidecarItem>
        )}
        {cluster?.name && (
          <SidecarItem heading="Cluster name">
            <InlineLink
              as={Link}
              to={`/${CD_REL_PATH}/${CLUSTERS_REL_PATH}/${cluster.id}`}
            >
              {cluster.name}
            </InlineLink>
          </SidecarItem>
        )}
      </Sidecar>
    </div>
  )
}
