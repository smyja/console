import { ResponsiveLine } from '@nivo/line'
import { EmptyState } from '@pluralsh/design-system'
import dayjs from 'dayjs'
import { ClusterUsageHistoryFragment } from 'generated/graphql'
import styled from 'styled-components'
import { COLORS } from 'utils/color'
import { formatDateTime } from 'utils/datetime'
import { SliceTooltip, useGraphTheme } from '../../utils/Graph'
import { dollarize } from '../ClusterUsagesTableCols'
import { LineGraphData } from 'components/utils/NivoLineForecastingLayer'

export const GRAPH_CARD_MAX_HEIGHT = 330

export function CostTimeSeriesGraph({
  history,
}: {
  history: ClusterUsageHistoryFragment[]
}) {
  const graphTheme = useGraphTheme()
  const data = getGraphData(history)

  if (!data) return <EmptyState message="No time-series data available" />

  return (
    <GraphWrapperSC>
      <ResponsiveLine
        // @ts-ignore, best for this to just be a fixed size
        height={GRAPH_CARD_MAX_HEIGHT}
        theme={graphTheme}
        data={data}
        tooltip={SliceTooltip}
        colors={COLORS}
        margin={{ top: 32, right: 128, bottom: 64, left: 64 }}
        xScale={{ type: 'time' }}
        yScale={{
          type: 'linear',
          min: 'auto',
          max: 'auto',
        }}
        yFormat={dollarize}
        curve="natural"
        axisBottom={{
          format: (value) => formatDateTime(value, 'M/DD'),
          legend: 'date',
          legendOffset: 36,
          legendPosition: 'middle',
        }}
        axisLeft={{
          format: (value) => `$${value}`,
          tickPadding: 5,
          tickRotation: 0,
          legend: 'cost',
          legendOffset: -50,
          legendPosition: 'middle',
          truncateTickAt: 0,
        }}
        xFormat={(value) => dayjs(value).format('MMM DD, YYYY')}
        pointSize={0}
        pointColor={{ theme: 'background' }}
        pointBorderWidth={2}
        pointBorderColor={{ from: 'serieColor' }}
        enableTouchCrosshair
        useMesh
        legends={[
          {
            anchor: 'bottom-right',
            direction: 'column',
            justify: false,
            translateX: 100,
            translateY: 0,
            itemsSpacing: 0,
            itemDirection: 'left-to-right',
            itemWidth: 80,
            itemHeight: 32,
            itemOpacity: 0.75,
            symbolSize: 12,
            symbolShape: 'circle',
            itemTextColor: 'white',
            effects: [
              {
                on: 'hover',
                style: {
                  itemBackground: 'rgba(0, 0, 0, .03)',
                  itemOpacity: 1,
                },
              },
            ],
          },
        ]}
      />
    </GraphWrapperSC>
  )
}

const getGraphData = (history: ClusterUsageHistoryFragment[]) => {
  const cpuData: LineGraphData = {
    id: 'CPU',
    data: [],
  }
  const memoryData: LineGraphData = {
    id: 'Memory',
    data: [],
  }
  const storageData: LineGraphData = {
    id: 'Storage',
    data: [],
  }

  const timestamps = new Set()
  history.forEach((point) => {
    if (!timestamps.has(point.timestamp)) {
      cpuData.data.push({
        x: new Date(point.timestamp),
        y: point.cpuCost ?? null,
      })
      memoryData.data.push({
        x: new Date(point.timestamp),
        y: point.memoryCost ?? null,
      })
      storageData.data.push({
        x: new Date(point.timestamp),
        y: point.storageCost ? point.storageCost : null,
      })

      timestamps.add(point.timestamp)
    }
  })

  const data = [cpuData, memoryData, storageData]

  // return null instead of empty arrays if there's no data at all
  return data.some((obj) => obj.data.length > 0) ? data : null
}

const GraphWrapperSC = styled.div((_) => ({
  height: '100%',
  width: '100%',
}))
