import { useQuery } from '@apollo/client'

import { Div } from 'honorable'

import { EmptyState, LoopingLogo, SearchIcon } from '@pluralsh/design-system'

import { useContext, useEffect, useState } from 'react'

import { StandardScroller } from 'components/utils/SmoothScroller'
import { isEmpty } from 'lodash'
import { LoginContext } from 'components/contexts'

import { List, ListItem } from '../../utils/List'
import ListInput from '../../utils/ListInput'
import { extendConnection } from '../../../utils/graphql'

import UserInvite from './UserInvite'
import { USERS_Q } from './queries'
import { User } from './User'

export default function UsersList() {
  const { configuration } = useContext<any>(LoginContext)
  const [q, setQ] = useState('')
  const [listRef, setListRef] = useState<any>(null)
  const { data, loading, fetchMore } = useQuery(USERS_Q, { variables: { q } })
  const [dataCache, setDataCache] = useState(data)

  useEffect(() => {
    if (data) setDataCache(data)
  }, [data])

  if (!data && !dataCache) return <LoopingLogo />

  const { edges, pageInfo } = data?.users || dataCache?.users || {}

  return (
    <List>
      <ListInput
        width="100%"
        value={q}
        placeholder="Search a user"
        startIcon={<SearchIcon color="text-light" />}
        onChange={({ target: { value } }) => setQ(value)}
        flexGrow={0}
      />
      <Div
        flexGrow={1}
        width="100%"
      >
        {edges?.length > 0 ? (
          <StandardScroller
            listRef={listRef}
            setListRef={setListRef}
            items={edges}
            mapper={({ node: user }, { prev, next }) => (
              <ListItem
                first={!prev.node}
                last={!next.node}
              >
                <User
                  user={user}
                />
              </ListItem>
            )}
            loadNextPage={() => pageInfo.hasNextPage && fetchMore({
              variables: { cursor: pageInfo.endCursor },
              updateQuery: (prev, { fetchMoreResult: { users } }) => extendConnection(prev, users, 'users'),
            })}
            hasNextPage={pageInfo.hasNextPage}
            loading={loading}
            placeholder={() => (
              <Div
                flex={false}
                height="50px"
                padding="small"
              />
            )}
            handleScroll={undefined}
            refreshKey={undefined}
            setLoader={undefined}
          />
        ) : (
          <EmptyState
            message={isEmpty(q)
              ? "Looks like you don't have any groups yet."
              : `No users found for ${q}`}
          >
            {/* Invites are only available when not using login with Plural. */}
            {configuration && !configuration?.pluralLogin && <UserInvite />}
          </EmptyState>
        )}
      </Div>
    </List>
  )
}