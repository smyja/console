import { ErrorIcon, IconFrame } from '@pluralsh/design-system'
import { useContext } from 'react'
import styled from 'styled-components'
import { formatDateTime } from 'utils/datetime'

import SubscriptionContext from '../contexts/SubscriptionContext'

const Wrap = styled.div({ display: 'flex', alignItems: 'center' })

const Message = styled.p(({ theme }) => ({
  ...theme.partials.text.overline,
  color: theme.colors['text-xlight'],
}))

const MessageLink = styled.a(({ theme }) => ({
  ...theme.partials.text.inlineLink,
}))

export default function BillingLegacyUserMessage() {
  const { isPaidPlan, isGrandfathered, isGrandfatheringExpired, account } =
    useContext(SubscriptionContext)

  if (isPaidPlan || !(isGrandfathered || isGrandfatheringExpired)) return null

  const message = isGrandfatheringExpired
    ? 'Legacy user access expired. '
    : `Legacy user access until ${formatDateTime(
        account?.grandfatheredUntil,
        'MMM DD, YYYY'
      )}. `

  return (
    <Wrap>
      {isGrandfatheringExpired && (
        <IconFrame
          icon={<ErrorIcon color="icon-error" />}
          textValue={message}
        />
      )}
      <Message>
        {message}
        <MessageLink
          href="https://app.plural.sh/account/billing"
          target="_blank"
          rel="noopener noreferrer"
        >
          Upgrade now
        </MessageLink>
      </Message>
    </Wrap>
  )
}
