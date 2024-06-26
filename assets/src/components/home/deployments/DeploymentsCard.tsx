import { useFetchPaginatedData } from 'components/cd/utils/useFetchPaginatedData'

import {
  ServiceDeploymentStatus,
  useServiceDeploymentsQuery,
} from 'generated/graphql'
import {
  SERVICES_QUERY_PAGE_SIZE,
  SERVICES_REACT_VIRTUAL_OPTIONS,
} from 'components/cd/services/Services'
import { GqlError } from 'components/utils/Alert'
import pluralize from 'pluralize'

import { Title2H1 } from '../../utils/typography/Text'
import { HOME_CARD_MAX_HEIGHT } from '../HomeCard'

import { useProjectId } from '../../contexts/ProjectsContext'

import { DeploymentsTable } from './DeploymentsTable'

export function DeploymentsCard() {
  const projectId = useProjectId()
  const {
    data,
    loading,
    error,
    refetch,
    pageInfo,
    fetchNextPage,
    setVirtualSlice,
  } = useFetchPaginatedData(
    {
      queryHook: useServiceDeploymentsQuery,
      pageSize: SERVICES_QUERY_PAGE_SIZE,
      keyPath: ['serviceDeployments'],
    },
    {
      status: ServiceDeploymentStatus.Failed,
      projectId,
    }
  )

  if (error) {
    return <GqlError error={error} />
  }

  const numDeployments = data?.serviceDeployments?.edges?.length

  return (
    <div>
      <Title2H1>
        {numDeployments} {pluralize('deployment', numDeployments)} creating
        errors
      </Title2H1>
      <DeploymentsTable
        data={data?.serviceDeployments?.edges}
        emptyStateProps={{ message: 'All services healthy!' }}
        refetch={refetch}
        virtualizeRows
        hasNextPage={pageInfo?.hasNextPage}
        fetchNextPage={fetchNextPage}
        isFetchingNextPage={loading}
        reactVirtualOptions={SERVICES_REACT_VIRTUAL_OPTIONS}
        onVirtualSliceChange={setVirtualSlice}
        css={{ maxHeight: HOME_CARD_MAX_HEIGHT }}
      />
    </div>
  )
}
