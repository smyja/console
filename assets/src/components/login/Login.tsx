import { ApolloError, useMutation, useQuery } from '@apollo/client'
import { Button, LoopingLogo } from '@pluralsh/design-system'
import { WelcomeHeader } from 'components/utils/WelcomeHeader'
import { User, useMeQuery } from 'generated/graphql'
import gql from 'graphql-tag'
import { Div, Flex, Form, P } from 'honorable'
import { RefObject, useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { isValidEmail } from 'utils/email'

import { useTheme } from 'styled-components'

import {
  setRefreshToken,
  setToken,
  wipeRefreshToken,
  wipeToken,
} from '../../helpers/auth'
import { localized } from '../../helpers/hostname'
import { LoginContextProvider } from '../contexts'
import { ME_Q, SIGNIN } from '../graphql/users'
import { LoginPortal } from '../login/LoginPortal'
import { GqlError } from '../utils/Alert'
import { LabelledInput } from '../utils/LabelledInput'

// 30 seconds
const POLL_INTERVAL = 30 * 1000
const LOGIN_INFO = gql`
  query LoginInfo($redirect: String) {
    loginInfo(redirect: $redirect) {
      oidcUri
      external
      oidcName
    }
  }
`

const setInputFocus = (ref: RefObject<any>) => {
  requestAnimationFrame(() => {
    ref.current?.querySelector('input')?.focus()
  })
}

function LoginError({
  me,
  error,
}: {
  me: Nullable<User>
  error: ApolloError | undefined
}) {
  useEffect(() => {
    if (!error?.networkError && !me) {
      const to = setTimeout(() => {
        wipeToken()
        wipeRefreshToken()
        window.location = '/login' as any as Location
      }, 2000)

      return () => clearTimeout(to)
    }
  }, [error?.networkError, me])

  console.error('Login error:', error)

  return (
    <LoginPortal>
      <LoopingLogo />
    </LoginPortal>
  )
}

export function GrantAccess() {
  const [jwt, setJwt] = useState('')

  return (
    <LoginPortal>
      <Div marginBottom="large">
        <WelcomeHeader
          textAlign="left"
          marginBottom="xxsmall"
        />
        <P
          body1
          color="text-xlight"
        >
          Enter the login token given to you to gain access
        </P>
      </Div>
      <LabelledInput
        value={jwt}
        width="100%"
        label="Login Token"
        onChange={setJwt}
      />
      <Button
        fill="horizontal"
        pad={{ vertical: '8px' }}
        margin={{ top: 'xsmall' }}
        onClick={() => {
          setToken(jwt)
          window.location = '/' as any as Location
        }}
        disabled={jwt === ''}
      >
        Get access
      </Button>
    </LoginPortal>
  )
}

export function EnsureLogin({ children }) {
  const { data, error, loading } = useMeQuery({
    pollInterval: POLL_INTERVAL,
    errorPolicy: 'ignore',
  })

  const loginContextValue = data

  if (error || (!loading && !data?.clusterInfo)) {
    return (
      <LoginError
        me={data?.me}
        error={error}
      />
    )
  }

  if (!data?.clusterInfo) return null

  return (
    <LoginContextProvider value={loginContextValue}>
      {children}
    </LoginContextProvider>
  )
}

function OIDCLogin({ oidcUri, external, oidcName }) {
  return (
    <LoginPortal>
      <Flex
        flexDirection="column"
        gap="xlarge"
      >
        <Flex
          flexDirection="column"
          gap="xsmall"
        >
          <WelcomeHeader />
          <P
            body1
            color="text-light"
            textAlign="center"
          >
            Connect to your Plural account for access to this Console.
          </P>
        </Flex>
        <Button
          id="plrl-login"
          fill="horizontal"
          label=""
          onClick={() => {
            window.location = oidcUri
          }}
        >
          Log in with {external ? oidcName || 'OIDC' : 'Plural'}
        </Button>
      </Flex>
    </LoginPortal>
  )
}

export default function Login() {
  const theme = useTheme()
  const navigate = useNavigate()
  const [form, setForm] = useState({ email: '', password: '' })
  const emailRef = useRef<any>()

  useEffect(() => {
    setInputFocus(emailRef)
  }, [])

  const { data } = useQuery(ME_Q)
  const { data: loginData } = useQuery(LOGIN_INFO, {
    variables: { redirect: localized('/oauth/callback') },
  })

  const [loginMutation, { loading: loginMLoading, error: loginMError }] =
    useMutation(SIGNIN, {
      variables: form,
      onCompleted: ({ signIn: { jwt, refreshToken } }) => {
        setToken(jwt)
        setRefreshToken(refreshToken?.token)
        navigate('/')
      },
      onError: console.error,
    })

  if (!loginMError && data?.me) {
    window.location = '/' as any as Location
  }

  if (loginData?.loginInfo?.oidcUri) {
    return (
      <OIDCLogin
        oidcUri={loginData.loginInfo.oidcUri}
        external={loginData.loginInfo.external}
        oidcName={loginData.loginInfo.oidcName}
      />
    )
  }

  const disabled = form.password.length === 0 || !isValidEmail(form.email)
  const onSubmit = (e) => {
    e.preventDefault()
    if (disabled) {
      return
    }
    loginMutation()
  }
  const passwordErrorMsg =
    loginMError?.message === 'invalid password' ? 'Invalid password' : undefined
  const loginError = !passwordErrorMsg && loginMError

  return (
    <LoginPortal>
      <WelcomeHeader marginBottom="xlarge" />
      <Form onSubmit={onSubmit}>
        <div
          css={{
            display: 'flex',
            flexDirection: 'column',
            marginBottom: 10,
            gap: theme.spacing.xsmall,
          }}
        >
          {loginMError && (
            <Div marginBottom="large">
              <GqlError
                header="Login failed"
                error={loginError}
              />
            </Div>
          )}
          <Flex
            flexDirection="column"
            gap="small"
            marginBottom="small"
          >
            <LabelledInput
              ref={emailRef}
              label="Email address"
              value={form.email}
              onChange={(email) => setForm({ ...form, email })}
              placeholder="Enter email address"
            />
            <LabelledInput
              label="Password"
              type="password"
              hint={passwordErrorMsg}
              error={!!passwordErrorMsg}
              value={form.password}
              onChange={(password) => setForm({ ...form, password })}
              placeholder="Enter password"
            />
          </Flex>
          <Button
            type="submit"
            fill="horizontal"
            pad={{ vertical: '8px' }}
            margin={{ top: 'xsmall' }}
            loading={loginMLoading}
            disabled={disabled}
          >
            Log in
          </Button>
        </div>
      </Form>
    </LoginPortal>
  )
}
