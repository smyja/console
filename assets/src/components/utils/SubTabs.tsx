import { Flex, SubTab } from '@pluralsh/design-system'
import { useParams } from 'react-router-dom'
import { LinkTabWrap } from './Tabs'

export type SubtabDirectory = {
  path: string
  label: string
}[]

export function SubTabs({ directory }: { directory: SubtabDirectory }) {
  const route = useParams()['*']

  return (
    <Flex>
      {directory.map(({ path, label }) => (
        <LinkTabWrap
          active={route?.includes(path)}
          key={path}
          textValue={label}
          to={path}
        >
          <SubTab>{label}</SubTab>
        </LinkTabWrap>
      ))}
    </Flex>
  )
}
