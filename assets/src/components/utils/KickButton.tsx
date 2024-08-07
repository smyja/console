import {
  Button,
  GraphQLToast,
  IconFrame,
  ReloadIcon,
  Spinner,
  Tooltip,
} from '@pluralsh/design-system'
import { useSyncCooldown } from 'components/hooks/useSyncCooldown'
import { useState } from 'react'
import { ButtonProps } from 'honorable'

export default function KickButton({
  pulledAt,
  kickMutationHook,
  message,
  icon = false,
  tooltipMessage,
  variables,
  ...props
}: {
  pulledAt?: string | null
  kickMutationHook: any
  message?: string
  icon?: boolean
  tooltipMessage: string
  variables: any
} & ButtonProps) {
  const [mutation, { loading, error }] = kickMutationHook({ variables })
  const [buttonClicked, setButtonClicked] = useState(false)

  const lastPullPlus15 =
    typeof pulledAt === 'string'
      ? new Date(new Date(pulledAt).getTime() + 15 * 1000)
      : null
  const { disabled, secondsRemaining } = useSyncCooldown(lastPullPlus15)

  return (
    <div>
      {error && disabled && (
        <GraphQLToast
          error={{ ...error }}
          header="Error (500)"
          margin="xlarge"
          marginVertical="xxxlarge"
        />
      )}
      <Tooltip
        label={
          <TooltipLabel
            pulledAt={pulledAt}
            message={tooltipMessage}
          />
        }
      >
        {icon ? (
          <IconFrame
            icon={
              loading ? (
                <Spinner />
              ) : (
                <ReloadIcon
                  color={
                    disabled && buttonClicked ? 'icon-disabled' : undefined
                  }
                />
              )
            }
            type="secondary"
            disabled={disabled && buttonClicked}
            clickable
            onClick={() => {
              setButtonClicked(true)
              mutation()
            }}
          />
        ) : (
          <Button
            disabled={disabled && buttonClicked}
            onClick={() => {
              setButtonClicked(true)
              mutation()
            }}
            loading={loading}
            {...props}
          >
            {disabled && buttonClicked
              ? `Resync cooldown ${secondsRemaining}`
              : message}
          </Button>
        )}
      </Tooltip>
    </div>
  )
}

function TooltipLabel({
  pulledAt,
  message,
}: {
  pulledAt?: string | null
  message?: string
}) {
  return (
    <>
      <p>{message}</p>
      {pulledAt && (
        <p>
          Last synced:{' '}
          {new Intl.DateTimeFormat('en-US', {
            year: 'numeric',
            month: 'short',
            day: 'numeric',
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit',
            timeZoneName: 'short',
          }).format(new Date(pulledAt))}
        </p>
      )}
    </>
  )
}
