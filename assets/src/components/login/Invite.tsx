import { useMutation, useQuery } from '@apollo/client'
import { Button, Flex } from '@pluralsh/design-system'
import { GqlError } from 'components/utils/Alert'
import { WelcomeHeader } from 'components/utils/WelcomeHeader'
import { ComponentProps, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'

import { setRefreshToken, setToken } from '../../helpers/auth'

import { INVITE_Q, SIGNUP } from '../graphql/users'
import { LabelledInput } from '../utils/LabelledInput'

import { Body1P, CaptionP } from 'components/utils/typography/Text'
import { useTheme } from 'styled-components'
import { LoginPortal } from './LoginPortal'
import {
  PasswordError,
  PasswordErrorCode,
  PasswordErrorMessage,
  validatePassword,
} from './PasswordValidation'

function InvalidInvite() {
  return (
    <Flex
      width="100vw"
      height="100vh"
      justifyContent="center"
      alignItems="center"
    >
      This invite code is no longer valid
    </Flex>
  )
}

function PasswordErrorMsg({ errorCode }: { errorCode: PasswordErrorCode }) {
  return (
    <CaptionP $color="text-danger">{PasswordErrorMessage[errorCode]}</CaptionP>
  )
}

export function SetPasswordField({
  errorCode,
  ...props
}: { errorCode?: PasswordErrorCode } & Omit<
  ComponentProps<typeof LabelledInput>,
  'errorCode'
>) {
  return (
    <LabelledInput
      required
      label="Password"
      type="password"
      placeholder="Enter password"
      hint="10 character minimum"
      caption={
        errorCode === PasswordError.TooShort && (
          <PasswordErrorMsg errorCode={errorCode} />
        )
      }
      error={errorCode === PasswordError.TooShort}
      {...props}
    />
  )
}

export function ConfirmPasswordField({
  errorCode,
  ...props
}: ComponentProps<typeof SetPasswordField>) {
  return (
    <LabelledInput
      required
      label="Confirm password"
      type="password"
      placeholder="Confirm password"
      hint=""
      caption={
        errorCode === PasswordError.NoMatch && (
          <PasswordErrorMsg errorCode={errorCode} />
        )
      }
      error={errorCode === PasswordError.NoMatch}
      {...props}
    />
  )
}

export default function Invite() {
  const { spacing } = useTheme()
  const navigate = useNavigate()
  const { inviteId } = useParams()
  const [attributes, setAttributes] = useState({ name: '', password: '' })
  const [confirm, setConfirm] = useState('')
  const [mutation, { loading, error: signupError }] = useMutation(SIGNUP, {
    variables: { inviteId, attributes },
    onCompleted: ({ signup: { jwt, refreshToken } }) => {
      setToken(jwt)
      setRefreshToken(refreshToken?.token)
      navigate('/')
    },
    onError: console.error,
  })
  const { data, error } = useQuery(INVITE_Q, { variables: { id: inviteId } })

  if (error || (data && !data.invite)) return <InvalidInvite />
  if (!data) return null

  const email = data?.invite?.email

  const { disabled: passwordDisabled, error: passwordError } = validatePassword(
    attributes.password,
    confirm
  )

  const isNameValid = attributes.name.length > 0
  const submitEnabled = isNameValid && !passwordDisabled && email

  const onSubmit = (e) => {
    e.preventDefault()
    if (!submitEnabled) {
      return
    }
    mutation()
  }

  return (
    <LoginPortal>
      <div css={{ marginBottom: spacing.xlarge }}>
        <WelcomeHeader
          textAlign="left"
          marginBottom="xxsmall"
        />
        <Body1P $color="text-xlight">
          You have been invited to join this Plural account. Create an account
          to join.
        </Body1P>
      </div>
      <form onSubmit={onSubmit}>
        {signupError && (
          <div css={{ marginBottom: spacing.large }}>
            <GqlError
              header="Signup failed"
              error={signupError}
            />
          </div>
        )}
        <Flex
          flexDirection="column"
          gap="small"
          marginBottom={spacing.small}
        >
          <LabelledInput
            label="Email"
            value={email}
            disabled
          />
          <LabelledInput
            label="Username"
            value={attributes.name}
            placeholder="Enter username"
            onChange={(name) => setAttributes({ ...attributes, name })}
            required
          />

          <SetPasswordField
            value={attributes.password}
            onChange={(password) => setAttributes({ ...attributes, password })}
            errorCode={passwordError}
          />
          <ConfirmPasswordField
            value={confirm}
            onChange={setConfirm}
            errorCode={passwordError}
          />
        </Flex>
        <Button
          type="submit"
          primary
          width="100%"
          loading={loading}
          disabled={!submitEnabled}
        >
          Sign up
        </Button>
      </form>
    </LoginPortal>
  )
}
