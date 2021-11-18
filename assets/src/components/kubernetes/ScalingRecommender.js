import React, { useCallback, useState } from 'react'
import { Tabs, TabHeader, TabHeaderItem, TabContent, Button, ModalHeader } from 'forge-core'
import { useQuery } from '@apollo/react-hooks'
import { SCALING_RECOMMENDATION } from './queries'
import { LoopingLogo } from '../utils/AnimatedLogo'
import { MetadataRow } from './Metadata'
import { Box, Layer, Text } from 'grommet'

const POLL_INTERVAL = 10000

function ScalingRecommendations({recommendations}) {
  return (
    <Box flex={false} pad='small'>
      <Tabs defaultTab='info'>
        <TabHeader>
          {recommendations.map(({name}) => (
            <TabHeaderItem key={name} name={name}>
              <Text size='small' weight={500}>{name}</Text>
            </TabHeaderItem>
          ))}
        </TabHeader>
        {recommendations.map((recommendation) => (
          <TabContent key={recommendation.name} name={recommendation.name}>
            <MetadataRow name='lower bound'>
              <Text size='small'>cpu: {recommendation.lowerBound?.requests?.cpu}, mem: {recommendation.lowerBound?.requests?.memory}</Text>
            </MetadataRow>
            <MetadataRow name='upper bound'>
              <Text size='small'>cpu: {recommendation.upperBound?.requests?.cpu}, mem: {recommendation.upperBound?.requests?.memory}</Text>
            </MetadataRow>
            <MetadataRow name='uncapped target'>
              <Text size='small'>cpu: {recommendation.uncappedTarget?.requests?.cpu}, mem: {recommendation.uncappedTarget?.requests?.memory}</Text>
            </MetadataRow>
          </TabContent>
        ))}
      </Tabs>
    </Box>
  )
}

export function ScalingRecommender({kind, name, namespace}) {
  const {data} = useQuery(SCALING_RECOMMENDATION, {
    variables: {kind, name, namespace},
    pollInterval: POLL_INTERVAL
  })

  const recommendations = data?.status?.recommendations

  return (
    <Box fill='horizontal' style={{minHeight: '250px', overflow: 'auto'}}>
      {recommendations ? <ScalingRecommendations recommendations={recommendations} /> : 
                         <LoopingLogo />}
    </Box>
  )
}

export function ScalingRecommenderModal({kind, name, namespace}) {
  const [open, setOpen] = useState(false)
  const close = useCallback(() => setOpen(false), [setOpen])

  return (
    <>
    <Button label='Scaling Recommendation' onClick={() => setOpen(true)} />
    {open && (
      <Layer onClickOutside={close} onEsc={close}>
        <Box width='50vw'>
          <ModalHeader text='Recommendations' setOpen={setOpen} />
          <ScalingRecommender kind={kind} name={name} namespace={namespace} />
        </Box>
      </Layer>
    )}
    </>
  )
}