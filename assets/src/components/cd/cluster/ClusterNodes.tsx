import { useOutletContext } from 'react-router-dom'
import { ColumnDef } from '@tanstack/react-table'
import { useMemo } from 'react'
import { useTheme } from 'styled-components'

import { Cluster } from 'generated/graphql'

import {
  ColCpuTotal,
  ColCpuUsage,
  ColMemoryTotal,
  ColMemoryUsage,
  ColName,
  ColRegion,
  ColStatus,
  ColZone,
  NodesList,
  TableData,
  columnHelper,
} from '../../cluster/nodes/NodesList'
import { TableCaretLink } from '../../cluster/TableElements'
import { getNodeDetailsPath } from '../../../routes/cdRoutesConsts'

export const ColActions = (clusterId?: string) =>
  columnHelper.accessor(() => null, {
    id: 'actions',
    cell: ({ row: { original } }) => (
      <TableCaretLink
        to={getNodeDetailsPath({
          clusterId,
          name: original?.name,
        })}
        textValue={`View node ${original?.name}`}
      />
    ),
    header: '',
  })

export default function ClusterNodes() {
  const theme = useTheme()
  const { cluster } = useOutletContext() as { cluster: Cluster }

  const columns: ColumnDef<TableData, any>[] = useMemo(
    () => [
      ColName,
      ColRegion,
      ColZone,
      ColCpuUsage,
      ColMemoryUsage,
      ColCpuTotal,
      ColMemoryTotal,
      ColStatus,
      ColActions(cluster?.id),
    ],
    [cluster]
  )

  // const usage: ResourceUsage = useMemo(() => {
  //   if (!cluster) {
  //     return null
  //   }
  //   const cpu = sumBy(
  //     cluster.nodeMetrics,
  //     (metrics) => cpuParser(metrics?.usage?.cpu) ?? 0
  //   )
  //   const mem = sumBy(
  //     cluster.nodeMetrics,
  //     (metrics) => memoryParser((metrics as any)?.usage?.memory) ?? 0
  //   )

  //   return { cpu, mem }
  // }, [cluster])

  return (
    <div
      css={{
        display: 'flex',
        flexDirection: 'column',
        gap: theme.spacing.medium,
      }}
    >
      {/* {!isEmpty(cluster.nodes) && prometheusConnection && (
        <ClusterMetrics
          nodes={cluster?.nodes?.filter((node): node is Node => !!node) || []}
          usage={usage}
          cluster={cluster}
        />
      )} */}
      <NodesList
        nodes={cluster?.nodes || []}
        nodeMetrics={cluster?.nodeMetrics || []}
        columns={columns}
        linkBasePath={getNodeDetailsPath({
          clusterId: cluster?.id,
          name: '',
          isRelative: false,
        })}
      />
    </div>
  )
}
