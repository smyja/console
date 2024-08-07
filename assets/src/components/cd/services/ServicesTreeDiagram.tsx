import { usePrevious } from '@pluralsh/design-system'
import {
  GlobalServiceFragment,
  ServiceDeployment,
  ServiceTreeNodeFragment,
} from 'generated/graphql'
import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useState,
} from 'react'
import {
  Edge,
  type Node,
  useEdgesState,
  useNodesState,
  useReactFlow,
} from 'reactflow'
import 'reactflow/dist/style.css'
import { useTheme } from 'styled-components'
import { chunk } from 'lodash'

import {
  type DagreDirection,
  getLayoutedElements,
} from '../pipelines/utils/nodeLayouter'
import { ReactFlowGraph } from '../../utils/reactflow/graph'

import { EdgeType } from '../../utils/reactflow/edges'

import { pairwise } from '../../../utils/array'

import {
  GlobalServiceNodeType,
  ServiceNodeType,
  nodeTypes,
} from './ServicesTreeDiagramNodes'

const isNotDeploymentOperatorService = (
  service: Pick<ServiceDeployment, 'name'>
) => service.name !== 'deploy-operator'

function getNodesAndEdges(
  services: ServiceTreeNodeFragment[],
  globalServices: GlobalServiceFragment[]
) {
  const nodes: Node[] = []
  const edges: Edge[] = []

  services.filter(isNotDeploymentOperatorService).forEach((service) => {
    nodes.push({
      id: service.id,
      position: { x: 0, y: 0 },
      type: ServiceNodeType,
      data: { ...service },
    })

    if (service.parent?.id && isNotDeploymentOperatorService(service.parent)) {
      edges.push({
        type: EdgeType.Smooth,
        updatable: false,
        id: `${service.id}${service.parent.id}`,
        source: service.parent.id,
        target: service.id,
      })
    }

    if (service.owner?.id) {
      edges.push({
        type: EdgeType.Smooth,
        updatable: false,
        id: `${service.id}${service.owner.id}`,
        source: service.owner.id,
        target: service.id,
      })
    }
  })

  globalServices.forEach((service) => {
    nodes.push({
      id: service.id,
      position: { x: 0, y: 0 },
      type: GlobalServiceNodeType,
      data: { ...service },
    })

    if (service.parent?.id && isNotDeploymentOperatorService(service.parent)) {
      edges.push({
        type: EdgeType.Smooth,
        updatable: false,
        id: `${service.id}${service.parent.id}`,
        source: service.parent.id,
        target: service.id,
      })
    }
  })

  positionOrphanedNodes(nodes, edges)

  return { nodes, edges }
}

function positionOrphanedNodes(nodes: Node[], edges: Edge[]) {
  const connectedNodes = new Set<string>()

  edges.forEach((edge) => {
    connectedNodes.add(edge.source)
    connectedNodes.add(edge.target)
  })

  const orphanedNodes = nodes.filter((node) => !connectedNodes.has(node.id))

  chunk(orphanedNodes, 3).forEach((chunk) => {
    for (const [source, target] of pairwise(chunk)) {
      edges.push({
        type: EdgeType.Invisible,
        updatable: false,
        id: `positioning${source.id}${target.id}`,
        source: source.id,
        target: target.id,
      })
    }
  })
}

export function ServicesTreeDiagram({
  services,
  globalServices,
}: {
  services: ServiceTreeNodeFragment[]
  globalServices: GlobalServiceFragment[]
}) {
  const theme = useTheme()

  const { nodes: initialNodes, edges: initialEdges } = useMemo(
    () => getNodesAndEdges(services, globalServices),
    [globalServices, services]
  )
  const { setViewport, getViewport, viewportInitialized } = useReactFlow()
  const [nodes, setNodes, onNodesChange] = useNodesState(initialNodes as any)
  const [edges, setEdges, onEdgesChange] = useEdgesState(initialEdges)
  const [needsLayout, setNeedsLayout] = useState(true)
  const prevServicesState = usePrevious(services)
  const prevGlobalServicesState = usePrevious(globalServices)
  const prevNodes = usePrevious(nodes)
  const prevEdges = usePrevious(edges)

  const layoutNodes = useCallback(
    (direction: DagreDirection = 'LR') => {
      const layouted = getLayoutedElements(nodes, edges, {
        direction,
        zoom: getViewport().zoom,
        gridGap: theme.spacing.large,
        margin: theme.spacing.large,
      })

      setNodes([...layouted.nodes])
      setEdges([...layouted.edges])
      setNeedsLayout(false)
    },
    [nodes, edges, getViewport, theme.spacing.large, setNodes, setEdges]
  )

  useLayoutEffect(() => {
    if (viewportInitialized && needsLayout) {
      layoutNodes()
      requestAnimationFrame(() => {
        layoutNodes()
      })
    }
  }, [
    viewportInitialized,
    needsLayout,
    nodes,
    prevNodes,
    edges,
    prevEdges,
    layoutNodes,
  ])

  useEffect(() => {
    // Don't run for initial value, only for changes
    if (
      (prevServicesState && prevServicesState !== services) ||
      (prevGlobalServicesState && prevGlobalServicesState !== globalServices)
    ) {
      const { nodes, edges } = getNodesAndEdges(services, globalServices)

      setNodes(nodes)
      setEdges(edges)
      setNeedsLayout(true)
    }
  }, [
    services,
    globalServices,
    prevServicesState,
    prevGlobalServicesState,
    setEdges,
    setNodes,
  ])

  return (
    <ReactFlowGraph
      allowFullscreen
      resetView={() => setViewport({ x: 0, y: 0, zoom: 1 }, { duration: 500 })}
      nodes={nodes}
      edges={edges}
      onNodesChange={onNodesChange}
      onEdgesChange={onEdgesChange}
      nodeTypes={nodeTypes}
    />
  )
}
