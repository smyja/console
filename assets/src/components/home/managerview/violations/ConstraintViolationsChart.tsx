import { RadialBar } from '@nivo/radial-bar'
import { ChartTooltip } from 'components/utils/ChartTooltip'
import {
  COLOR_MAP,
  createCenteredMetric,
} from 'components/utils/RadialBarChart'
import { PolicyStatisticsQuery } from 'generated/graphql'
import styled from 'styled-components'

import { useMemo } from 'react'

import { ChartSkeleton } from 'components/utils/SkeletonLoaders'

import { CustomLegend } from '../../CustomLegend'

const CHART_SIZE = 275

export function ConstraintViolationsChart({
  data,
}: {
  data: PolicyStatisticsQuery | undefined
}) {
  const chartColors = {
    green: COLOR_MAP.green,
    red: COLOR_MAP.red,
  }
  const { chartData, legendData } = useChartData(data || {}, chartColors)

  if (!data?.policyStatistics) {
    return <ChartSkeleton scale={0.75} />
  }

  const CenterLabel = createCenteredMetric(
    `${getPercentCompliance(data)}%`,
    `Compliance`
  )

  return (
    <ViewWrapperSC>
      <RadialBar
        colors={(item) => chartColors[item.data.color]}
        endAngle={360}
        cornerRadius={5}
        padAngle={1}
        padding={0.6}
        innerRadius={0.4}
        tooltip={(props) => (
          <ChartTooltip
            color={props.bar.color}
            value={props.bar.formattedValue}
            label={props.bar.category}
          />
        )}
        layers={['bars', CenterLabel]}
        data={chartData}
        height={CHART_SIZE}
        width={CHART_SIZE}
      />
      {legendData.map((legend, index) => (
        <CustomLegend
          key={index}
          data={legend}
        />
      ))}
    </ViewWrapperSC>
  )
}

const ViewWrapperSC = styled.div({
  display: 'flex',
  flexDirection: 'column',
  alignItems: 'center',
  height: '100%',
})

const useChartData = (
  data: PolicyStatisticsQuery,
  colorMap: Record<string, string>
) => {
  const numWithViolations =
    data?.policyStatistics?.find((stat) => stat?.aggregate === 'exists')
      ?.count ?? 0
  const numWithoutViolations =
    data?.policyStatistics?.find((stat) => stat?.aggregate === 'none')?.count ??
    0

  return useMemo(() => {
    const chartData = [
      {
        id: 'compliance',
        data: [
          {
            color: 'red',
            x: 'With Violations',
            y: numWithViolations,
          },
          {
            color: 'green',
            x: 'Without Violations',
            y: numWithoutViolations || 0,
          },
        ],
      },
    ]
    const legendData = chartData
      .map((legend) =>
        legend.data.map((val) => ({
          label: val.x,
          value: val.y,
          color: colorMap[val.color],
        }))
      )
      .reverse()

    return { chartData, legendData }
  }, [numWithViolations, numWithoutViolations, colorMap])
}

const getPercentCompliance = (data: PolicyStatisticsQuery) => {
  if (!data?.policyStatistics) return 0

  const total = data.policyStatistics.reduce(
    (sum, val) => sum + (val?.count || 0),
    0
  )
  const numCompliant =
    data.policyStatistics.find((stat) => stat?.aggregate === 'none')?.count || 0

  return Math.round((numCompliant / total) * 100)
}
