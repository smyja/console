import { FullHeightTableWrap } from 'components/utils/layout/FullHeightTableWrap'
import {
  Breadcrumb,
  CaretRightIcon,
  GearTrainIcon,
  IconFrame,
  Table,
  Tooltip,
  useSetBreadcrumbs,
} from '@pluralsh/design-system'
import { ClustersRowFragment, useClustersQuery } from 'generated/graphql'
import { ComponentProps, useMemo } from 'react'
import { isEmpty } from 'lodash'
import LoadingIndicator from 'components/utils/LoadingIndicator'
import { createColumnHelper } from '@tanstack/react-table'
import { Link, useNavigate } from 'react-router-dom'
import styled, { useTheme } from 'styled-components'
import { ColWithIcon } from 'components/utils/table/ColWithIcon'
import { getProviderIconURL, getProviderName } from 'components/utils/Provider'
import { Edge } from 'utils/graphql'
import {
  CD_REL_PATH,
  CLUSTERS_REL_PATH,
  GLOBAL_SETTINGS_ABS_PATH,
} from 'routes/cdRoutesConsts'
import chroma from 'chroma-js'
import { nextSupportedVersion, toNiceVersion } from 'utils/semver'
import { roundToTwoPlaces } from 'components/cluster/utils'
import { BasicLink } from 'components/utils/typography/BasicLink'
import {
  cpuFormat,
  cpuParser,
  memoryFormat,
  memoryParser,
} from 'utils/kubernetes'
import { UsageBar } from 'components/cluster/nodes/UsageBar'
import { TableText } from 'components/cluster/TableElements'

import {
  POLL_INTERVAL,
  useSetCDHeaderContent,
  useSetCDScrollable,
} from '../ContinuousDeployment'
import { DeleteCluster } from '../providers/DeleteCluster'
import { useCDEnabled } from '../utils/useCDEnabled'
import { DEMO_CLUSTERS } from '../utils/demoData'

import ClusterUpgrade from './ClusterUpgrade'
import { ClusterHealth } from './ClusterHealthChip'
import CreateCluster from './create/CreateCluster'
import { ClusterConditions } from './ClusterConditions'
import { DynamicClusterIcon } from './DynamicClusterIcon'
import { DemoTable } from './ClustersDemoTable'
import { ClustersGettingStarted } from './ClustersGettingStarted'

export const CD_CLUSTERS_BASE_CRUMBS: Breadcrumb[] = [
  { label: 'cd', url: '/cd' },
  { label: 'clusters', url: `${CD_REL_PATH}/${CLUSTERS_REL_PATH}` },
]

const columnHelper = createColumnHelper<Edge<ClustersRowFragment>>()

export function StackedText({ first, second }) {
  const theme = useTheme()

  return (
    <>
      <div>{first}</div>
      {second && (
        <div
          css={{
            ...theme.partials.text.caption,
            color: theme.colors['text-xlight'],
          }}
        >
          {second}
        </div>
      )}
    </>
  )
}

export const columns = [
  columnHelper.accessor(({ node }) => node, {
    id: 'cluster',
    header: 'Cluster',
    cell: function Cell({
      getValue,
      row: {
        original: { node },
      },
    }) {
      const cluster = getValue()
      const different =
        !node?.self &&
        !!node?.currentVersion &&
        !!node?.version &&
        node?.currentVersion !== node?.version

      return (
        <div css={{ display: 'flex' }}>
          <ColWithIcon
            icon={
              <DynamicClusterIcon
                deleting={!!cluster?.deletedAt}
                upgrading={different}
                protect={!!cluster?.protect}
                self={!!cluster?.self}
              />
            }
          >
            <StackedText
              first={
                <BasicLink
                  as={Link}
                  to={`/cd/clusters/${cluster?.id}`}
                  css={{ whiteSpace: 'nowrap' }}
                >
                  {cluster?.name}
                </BasicLink>
              }
              second={`handle: ${cluster?.handle}`}
            />
          </ColWithIcon>
        </div>
      )
    },
  }),
  columnHelper.accessor(({ node }) => node?.provider, {
    id: 'cloud',
    header: 'Cloud',
    cell: function Cell({ getValue }) {
      const provider = getValue()
      const theme = useTheme()

      return (
        <ColWithIcon
          icon={getProviderIconURL(
            provider?.cloud ?? '',
            theme.mode === 'dark'
          )}
        >
          {getProviderName(provider?.cloud)}
        </ColWithIcon>
      )
    },
  }),
  columnHelper.accessor(({ node }) => node, {
    id: 'health',
    header: 'Health',
    cell: ({ getValue }) => <ClusterHealth cluster={getValue() || undefined} />,
  }),
  columnHelper.accessor(({ node }) => node, {
    id: 'version',
    header: 'Version',
    cell: function Cell({
      row: {
        original: { node },
      },
    }) {
      return (
        <div>
          {node?.currentVersion && (
            <StackedText
              first={`Current: ${toNiceVersion(node?.currentVersion)}`}
              second={
                node?.self || !node?.version
                  ? null
                  : `Target: ${toNiceVersion(node?.version)}`
              }
            />
          )}
          {!node?.currentVersion && <>-</>}
        </div>
      )
    },
  }),
  columnHelper.accessor(({ node }) => node, {
    id: 'cpu',
    header: 'CPU',
    cell: ({ getValue }) => {
      const cluster = getValue()
      const usage = cluster?.nodeMetrics?.reduce(
        (acc, current) => acc + (cpuParser(current?.usage?.cpu) ?? 0),
        0
      )
      const capacity = cluster?.nodes?.reduce(
        (acc, current) =>
          // @ts-ignore
          acc + (cpuParser(current?.status?.capacity?.cpu) ?? 0),
        0
      )
      const display = `${usage ? cpuFormat(roundToTwoPlaces(usage)) : '—'} / ${
        capacity ? cpuFormat(capacity) : '—'
      }`

      return usage !== undefined && !!capacity ? (
        <Tooltip
          label={display}
          placement="top"
        >
          <TableText>
            <UsageBar
              usage={usage / capacity}
              width={120}
            />
          </TableText>
        </Tooltip>
      ) : (
        display
      )
    },
  }),
  columnHelper.accessor(({ node }) => node, {
    id: 'memory',
    header: 'Memory',
    cell: ({ getValue }) => {
      const cluster = getValue()
      const usage = cluster?.nodeMetrics?.reduce(
        (acc, current) => acc + (memoryParser(current?.usage?.memory) ?? 0),
        0
      )
      const capacity = cluster?.nodes?.reduce(
        (acc, current) =>
          // @ts-ignore
          acc + (memoryParser(current?.status?.capacity?.memory) ?? 0),
        0
      )

      const display = `${usage ? memoryFormat(usage) : '—'} / ${
        capacity ? memoryFormat(capacity) : '—'
      }`

      return usage !== undefined && !!capacity ? (
        <Tooltip
          label={display}
          placement="top"
        >
          <TableText>
            <UsageBar
              usage={usage / capacity}
              width={120}
            />
          </TableText>
        </Tooltip>
      ) : (
        display
      )
    },
  }),
  columnHelper.accessor(({ node }) => node, {
    id: 'status',
    header: 'Status',
    cell: ({ table, getValue }) => {
      const cluster = getValue()
      const hasDeprecations = !isEmpty(cluster?.apiDeprecations)
      const upgrade = nextSupportedVersion(
        cluster?.version,
        cluster?.provider?.supportedVersions
      )
      const { refetch } = table.options.meta as { refetch?: () => void }

      return (
        (!!upgrade || hasDeprecations) &&
        !cluster?.self && (
          <ClusterUpgrade
            cluster={cluster}
            refetch={refetch}
          />
        )
      )
    },
  }),
  columnHelper.accessor(({ node }) => node?.status?.conditions?.length ?? 0, {
    id: 'conditions',
    header: 'Conditions',
    cell: ({ row: { original } }) =>
      original?.node?.status?.conditions && (
        <ClusterConditions cluster={original.node} />
      ),
  }),
  columnHelper.accessor(({ node }) => node, {
    id: 'actions',
    header: '',
    cell: function Cell({ table, getValue }) {
      const navigate = useNavigate()
      const cluster = getValue()
      const { refetch } = table.options.meta as { refetch?: () => void }

      return (
        <div css={{ alignItems: 'center', alignSelf: 'end', display: 'flex' }}>
          {cluster && (
            <DeleteCluster
              cluster={cluster}
              refetch={refetch}
            />
          )}
          <IconFrame
            clickable
            onClick={() =>
              navigate(`/${CD_REL_PATH}/${CLUSTERS_REL_PATH}/${cluster?.id}`)
            }
            size="medium"
            icon={<CaretRightIcon />}
            textValue="Go to cluster details"
            tooltip
            type="tertiary"
          />
        </div>
      )
    },
  }),
]

type TableWrapperSCProps = {
  $blurred: boolean
}
export const TableWrapperSC = styled(FullHeightTableWrap)<TableWrapperSCProps>(
  ({ theme, $blurred }) => ({
    '&&': {
      ...($blurred
        ? {
            position: 'relative',
            height: 'fit-content',
            // maxHeight: 300,
            pointerEvents: 'none',
            '&:before': {
              content: '""',
              position: 'absolute',
              top: -5,
              left: -5,
              right: -5,
              bottom: -5,
              zIndex: 10,
              background: `linear-gradient(180deg, ${chroma(
                theme.colors['fill-zero']
              ).alpha(0.1)} 0%, ${theme.colors['fill-zero']} 100%)`,
              backdropFilter: `blur(1px)`,
            },
          }
        : {}),
    },
  })
)

export default function Clusters() {
  const theme = useTheme()
  const navigate = useNavigate()
  const cdIsEnabled = useCDEnabled()
  const { data, refetch } = useClustersQuery({
    fetchPolicy: 'cache-and-network',
    pollInterval: POLL_INTERVAL,
  })
  const headerActions = useMemo(
    () =>
      cdIsEnabled ? (
        <div
          css={{
            display: 'flex',
            justifyContent: 'end',
            gap: theme.spacing.large,
          }}
        >
          <IconFrame
            type="secondary"
            size="large"
            tooltip="Global settings"
            clickable
            icon={<GearTrainIcon />}
            onClick={() => navigate(GLOBAL_SETTINGS_ABS_PATH)}
          />
          <CreateCluster />
        </div>
      ) : null,
    [cdIsEnabled, navigate, theme.spacing.large]
  )

  useSetCDHeaderContent(headerActions)
  useSetBreadcrumbs(CD_CLUSTERS_BASE_CRUMBS)

  const clusterEdges = data?.clusters?.edges
  const isDemo = isEmpty(clusterEdges) || !cdIsEnabled
  const tableData = isDemo ? DEMO_CLUSTERS : clusterEdges
  const showGettingStarted = isDemo || (clusterEdges?.length ?? 0) < 2

  useSetCDScrollable(showGettingStarted || isDemo)

  if (!data) {
    return <LoadingIndicator />
  }

  return (
    <>
      {!isDemo ? (
        <FullHeightTableWrap>
          <ClustersTable
            data={tableData || []}
            refetch={refetch}
          />
        </FullHeightTableWrap>
      ) : (
        <DemoTable mode={cdIsEnabled ? 'empty' : 'disabled'} />
      )}
      {showGettingStarted && <ClustersGettingStarted />}
    </>
  )
}

export function ClustersTable({
  refetch,
  data,
}: {
  refetch?: () => void
  data: any[]
}) {
  const reactTableOptions: ComponentProps<typeof Table>['reactTableOptions'] =
    useMemo(() => ({ meta: { refetch } }), [refetch])

  return (
    <Table
      loose
      data={data || []}
      columns={columns}
      reactTableOptions={reactTableOptions}
      css={{
        maxHeight: 'unset',
        height: '100%',
      }}
    />
  )
}