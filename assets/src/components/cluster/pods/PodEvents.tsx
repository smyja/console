import { useQuery } from '@apollo/client'
import { useParams } from 'react-router-dom'
import type { Event } from 'generated/graphql'
import { ScrollablePage } from 'components/utils/layout/ScrollablePage'
import LoadingIndicator from 'components/utils/LoadingIndicator'

import { POD_EVENTS_Q } from '../queries'
import EventsTable from '../../utils/EventsTable'

export default function NodeEvents() {
  const { name, namespace } = useParams()
  const { data } = useQuery<{ pod: { events: Event[] } }>(POD_EVENTS_Q, {
    variables: { name, namespace },
    fetchPolicy: 'cache-and-network',
  })

  if (!data) return <LoadingIndicator />

  const {
    pod: { events },
  } = data

  return (
    <ScrollablePage heading="Events">
      <EventsTable events={events || []} />
    </ScrollablePage>
  )
}
