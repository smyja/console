import React, { useContext, useEffect } from 'react'
import { Box, Text, ThemeContext } from 'grommet'
import { useQuery } from '@apollo/react-hooks'
import { ApplicationIcon, hasIcon, InstallationContext, useEnsureCurrent } from '../Installations'
import { RUNBOOKS_Q } from './queries'
import { boxShadow, HEADER_HEIGHT } from '../Builds'
import { useHistory, useParams } from 'react-router'
import { POLL_INTERVAL } from './constants'
import { BreadcrumbsContext } from '../Breadcrumbs'
import { StatusIcon } from './StatusIcon'

function RunbookRow({runbook, namespace}) {
  let hist = useHistory()
  const theme = useContext(ThemeContext)
  const {name, description} = runbook.spec

  return (
    <Box style={boxShadow(theme)} pad='small' round='xsmall'  direction='row' gap='small'
         background='cardDarkLight' hoverIndicator='sidebar' align='center'
         onClick={() => hist.push(`/runbooks/${namespace}/${runbook.name}`)}>
      <StatusIcon status={runbook.status} size={30} innerSize={14} />
      <Box fill='horizontal' gap='xsmall'>
        <Text size='small' weight={500}>{name}</Text>
        <Text size='small' color='dark-3' truncate>{description}</Text>
      </Box>
    </Box>
  )
}

export function Runbooks() {
  let history = useHistory()
  const {repo} = useParams()
  const {currentApplication, setOnChange} = useContext(InstallationContext)
  const {data} = useQuery(RUNBOOKS_Q, {
    variables: {namespace: currentApplication.name},
    fetchPolicy: 'cache-and-network',
    pollInterval: POLL_INTERVAL
  })

  const {setBreadcrumbs} = useContext(BreadcrumbsContext)
  useEffect(() => {
    setBreadcrumbs([
      {text: 'runbooks', url: '/runbooks'},
      {text: currentApplication.name, url: `/runbooks/${currentApplication.name}`}
    ])
  }, [currentApplication])

  useEffect(() => {
    setOnChange({func: ({name}) => history.push(`/runbooks/${name}`)})
  }, [])
  useEnsureCurrent(repo)

  const namespace = currentApplication.name

  return (
    <Box fill pad='small' background='backgroundColor'>
      <Box flex={false} direction='row' align='center' height={HEADER_HEIGHT}>
        <Box direction='row' fill='horizontal' gap='small' align='center' margin={{bottom: 'small'}}>
          {hasIcon(currentApplication) && <ApplicationIcon application={currentApplication} size='40px' dark />}
          <Box>
            <Text weight='bold' size='small'>{currentApplication.name}</Text>
            <Text size='small'>a collection of runbooks to help operate this application</Text>
          </Box>
        </Box>
      </Box>
      <Box fill gap='xsmall'>
        {data && data.runbooks.map((book) => <RunbookRow key={book.name} runbook={book} namespace={namespace} />)}
      </Box>
    </Box>
  )
}