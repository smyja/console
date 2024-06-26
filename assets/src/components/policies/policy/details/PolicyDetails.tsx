import { Chip, ErrorIcon, Sidecar, SidecarItem } from '@pluralsh/design-system'
import { Body1P, Title2H1 } from 'components/utils/typography/Text'
import { PolicyConstraintQuery } from 'generated/graphql'
import { A } from 'honorable'
import moment from 'moment'
import { Link } from 'react-router-dom'
import { getClusterDetailsPath } from 'routes/cdRoutesConsts'

import { useTheme } from 'styled-components'

import { ScrollablePage } from '../../../utils/layout/ScrollablePage'

function PolicyDetails({
  policy,
}: {
  policy?: PolicyConstraintQuery['policyConstraint']
}) {
  const theme = useTheme()

  if (!policy) {
    return null
  }
  const { name, cluster, violationCount, insertedAt, updatedAt, object } =
    policy

  return (
    <div
      css={{
        display: 'flex',
        flexGrow: 1,
        alignItems: 'flex-start',
        gap: theme.spacing.xlarge,
        height: '100%',
      }}
    >
      <div css={{ flexGrow: 1, height: '100%' }}>
        <ScrollablePage
          heading={name}
          scrollable
          fullWidth
        >
          <Title2H1 css={{ marginTop: 0 }}>Description</Title2H1>
          <Body1P css={{ color: theme.colors['text-long-form'] }}>
            {policy.description ||
              'No description found for this policy, this must be set in an annotation'}
          </Body1P>
          <Title2H1>Recommended action</Title2H1>
          <Body1P css={{ color: theme.colors['text-long-form'] }}>
            {policy.recommendation ||
              'No recommendation found for this policy, this must be set in an annotation'}
          </Body1P>
        </ScrollablePage>
      </div>
      <Sidecar
        width={200}
        minWidth={200}
        marginTop={57}
      >
        <SidecarItem heading="Policy name"> {name}</SidecarItem>
        <SidecarItem heading="Last Updated">
          {moment(updatedAt || insertedAt).format('M/D/YYYY')}
        </SidecarItem>
        <SidecarItem heading="Violations">
          <Chip
            icon={violationCount ? <ErrorIcon /> : undefined}
            severity={violationCount ? 'danger' : 'success'}
            width={violationCount ? 'auto' : 'fit-content'}
          >
            {violationCount}
          </Chip>
        </SidecarItem>
        {object?.metadata?.namespace && (
          <SidecarItem heading="Namespace">
            {object.metadata.namespace}
          </SidecarItem>
        )}
        {object?.kind && (
          <SidecarItem heading="Kind">{object.kind}</SidecarItem>
        )}
        {cluster && (
          <SidecarItem heading="Cluster name">
            <A
              as={Link}
              to={getClusterDetailsPath({ clusterId: cluster.id })}
              inline
            >
              {cluster.name}
            </A>
          </SidecarItem>
        )}
      </Sidecar>
    </div>
  )
}

export default PolicyDetails
