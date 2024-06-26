import { MutableRefObject, ReactNode, useRef } from 'react'
import {
  CheckOutlineIcon,
  GitHubLogoIcon,
  SubTab,
  TabList,
  TabListStateProps,
  TabPanel,
} from '@pluralsh/design-system'
import { useTheme } from 'styled-components'
import ProviderIcon from 'components/utils/Provider'
import { Provider } from 'generated/graphql-plural'

export enum RepoKind {
  Git = 'Git',
  Helm = 'Helm',
}

export function repoKindToLabel(repoKind: RepoKind) {
  return repoKind === RepoKind.Helm ? 'Helm' : 'Git'
}

export function RepoKindSelector({
  onKindChange,
  selectedKind,
  children,
  validKinds,
}: {
  onKindChange: any
  selectedKind: Nullable<string>
  children?: ReactNode
  validKinds?: Record<string, boolean>
}) {
  const theme = useTheme()
  const tabStateRef: MutableRefObject<any> = useRef()
  const orientation = 'horizontal'

  selectedKind = selectedKind || RepoKind.Git
  const tabListStateProps: TabListStateProps = {
    keyboardActivation: 'manual',
    orientation,
    selectedKey: selectedKind,
    onSelectionChange: onKindChange,
  }

  return (
    <>
      <TabList
        stateRef={tabStateRef}
        stateProps={tabListStateProps}
        css={{
          width: 'fit-content',
          position: 'relative',
          borderRadius: theme.borderRadiuses.medium,
          '&::after': {
            pointerEvents: 'none',
            content: '""',
            outline: theme.borders.default,
            position: 'absolute',
            top: 0,
            right: 0,
            bottom: 0,
            left: 0,
            outlineOffset: -1,
            borderRadius: theme.borderRadiuses.medium,
          },
        }}
      >
        <SubTab
          css={{
            display: 'flex',
            gap: theme.spacing.xsmall,
          }}
          key={RepoKind.Git}
          textValue={repoKindToLabel(RepoKind.Git)}
        >
          <GitHubLogoIcon color={theme.colors['icon-default']} />
          {repoKindToLabel(RepoKind.Git)}
          {validKinds?.[RepoKind.Git] && (
            <CheckOutlineIcon
              size={16}
              color={theme.colors['icon-success']}
            />
          )}
        </SubTab>
        <SubTab
          css={{
            display: 'flex',
            gap: theme.spacing.xsmall,
          }}
          key={RepoKind.Helm}
          textValue={repoKindToLabel(RepoKind.Helm)}
        >
          <div css={{ display: 'flex', alignItems: 'center' }}>
            <ProviderIcon
              provider={Provider.Generic}
              width={16}
            />
          </div>
          {repoKindToLabel(RepoKind.Helm)}
          {validKinds?.[RepoKind.Helm] && (
            <CheckOutlineIcon
              size={16}
              color={theme.colors['icon-success']}
            />
          )}
        </SubTab>
      </TabList>
      <TabPanel
        stateRef={tabStateRef}
        css={
          children
            ? {
                borderTop: theme.borders.default,
                paddingTop: theme.spacing.large,
              }
            : {}
        }
      >
        {children}
      </TabPanel>
    </>
  )
}
