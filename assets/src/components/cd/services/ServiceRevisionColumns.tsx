import {
  CheckRoundedIcon,
  HistoryIcon,
  IconFrame,
  Tooltip,
} from '@pluralsh/design-system'
import { createColumnHelper } from '@tanstack/react-table'
import { DateTimeCol } from 'components/utils/table/DateTimeCol'
import {
  ServiceDeploymentRevisionFragment,
  useRollbackServiceMutation,
} from 'generated/graphql'
import styled, { useTheme } from 'styled-components'
import { toDateOrUndef } from 'utils/datetime'

import { useState } from 'react'

import { Confirm } from 'components/utils/Confirm'
import { SelectedIcon } from 'components/utils/SelectedIcon'
import { StackedText } from 'components/utils/table/StackedText'

import { CaptionText } from 'components/cluster/TableElements'

import { useServiceContext } from './service/ServiceDetails'

const columnHelper =
  createColumnHelper<Nullable<ServiceDeploymentRevisionFragment>>()

const ColGitRef = columnHelper.accessor((row) => row, {
  id: 'gitRef',
  header: 'Revision',
  meta: { truncate: true },
  cell: ({ getValue }) => {
    const rev = getValue()
    const ref = rev?.helm?.chart
      ? `${rev.helm.chart}@${rev.helm.version}`
      : rev?.git?.ref

    return (
      <Tooltip
        placement="top-start"
        label={ref}
      >
        <StackedText
          first={ref}
          second={`sha: ${rev?.sha || ''}`}
        />
      </Tooltip>
    )
  },
})

const ColMessage = columnHelper.accessor((row) => row?.message, {
  id: 'commitMessage',
  header: 'Message',
  cell: ({ getValue }) => getValue(),
})

const ColCommitTime = columnHelper.accessor(
  (row) => toDateOrUndef(row?.insertedAt),
  {
    id: 'commitTime',
    header: 'Commit date',
    enableSorting: true,
    cell: ({ row: { original } }) => (
      <DateTimeCol date={original?.insertedAt} />
    ),
  }
)

const ColSelectedSC = styled.div((_) => ({
  display: 'flex',
  alignItems: 'center',
}))
const ColSelected = columnHelper.accessor(
  (row) => toDateOrUndef(row?.insertedAt),
  {
    id: 'selected',
    header: '',
    cell: function Cell({ row: { getIsSelected } }) {
      const theme = useTheme()

      return (
        <ColSelectedSC>
          {getIsSelected() && (
            <SelectedIcon
              size={16}
              color={theme.colors['action-primary']}
            />
          )}
        </ColSelectedSC>
      )
    },
  }
)

const ColActionsSC = styled.div((_) => ({
  display: 'flex',
  flexGrow: 1,
  alignItems: 'center',
  justifyContent: 'center',
}))
const ColActions = columnHelper.accessor((row) => row, {
  id: 'selected',
  header: '',
  cell: function Cell({ table, row: { original } }) {
    const theme = useTheme()

    const { service } = useServiceContext()
    const revision = original
    const { refetch } = table.options.meta as { refetch?: Nullable<() => void> }
    const [confirm, setConfirm] = useState(false)
    const [mutation, { loading, error }] = useRollbackServiceMutation({
      variables: {
        id: service?.id || '',
        revisionId: revision?.id || '',
      },
      onCompleted: () => {
        refetch?.()
        setConfirm(false)
      },
    })
    const { currentRevision } = table.options.meta as {
      currentRevision?: Nullable<ServiceDeploymentRevisionFragment>
    }

    const isCurrent = original?.id === currentRevision?.id

    return (
      <ColActionsSC>
        {isCurrent ? (
          <Tooltip
            placement="top"
            label="Current"
          >
            <div
              css={{
                width: 32,
                height: 32,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
              }}
            >
              <CheckRoundedIcon color="icon-success" />
            </div>
          </Tooltip>
        ) : (
          <IconFrame
            clickable
            tooltip="Roll back to this revision"
            type="floating"
            onClick={() => setConfirm(true)}
            icon={<HistoryIcon />}
          />
        )}
        <Confirm
          open={confirm}
          close={() => setConfirm(false)}
          label="Roll back"
          loading={loading}
          error={error}
          submit={() => mutation()}
          title="Roll back service deployment"
          text={
            <div
              css={{
                display: 'flex',
                flexDirection: 'column',
                gap: theme.spacing.small,
              }}
            >
              <p>
                Are you sure you want to roll back the service deployment to the
                following revision:
              </p>
              <p>
                <div>{revision?.git?.ref}</div>
                <CaptionText css={{ color: theme.colors['text-light'] }}>
                  sha: {revision?.sha}
                </CaptionText>
              </p>
            </div>
          }
        />
      </ColActionsSC>
    )
  },
})

export const selectableColumns = [
  ColGitRef,
  ColMessage,
  ColCommitTime,
  ColSelected,
]
export const columns = [ColGitRef, ColMessage, ColCommitTime, ColActions]
