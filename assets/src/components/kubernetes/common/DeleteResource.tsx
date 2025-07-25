import {
  ApolloError,
  FetchResult,
  LazyQueryExecFunction,
  ServerError,
  useMutation,
} from '@apollo/client'
import {
  Checkbox,
  FormField,
  IconFrame,
  ListBoxItem,
  Select,
  TrashCanIcon,
} from '@pluralsh/design-system'
import { ReactNode, useMemo, useState } from 'react'
import { useParams } from 'react-router-dom'
import { useTheme } from 'styled-components'
import {
  NamespacedResourceDeleteDocument,
  ResourceDeleteDocument,
} from '../../../generated/graphql-kubernetes'
import { KubernetesClient } from '../../../helpers/kubernetes.client'

import { Confirm, ConfirmProps } from '../../utils/Confirm'

import { Kind, Resource } from './types'

interface DeleteResourceProps {
  resource: Resource
  refetch?: Nullable<LazyQueryExecFunction<any, any>>
  customResource?: boolean
}

export default function DeleteResourceButton({
  resource,
  refetch,
  customResource = false,
}: DeleteResourceProps): ReactNode {
  const [open, setOpen] = useState(false)

  return (
    <div onClick={(e) => e.stopPropagation()}>
      <IconFrame
        clickable
        icon={<TrashCanIcon color="icon-danger" />}
        onClick={() => setOpen(true)}
        textValue="Delete"
        tooltip
      />
      {open && (
        <DeleteResourceModal
          open={open}
          setOpen={setOpen}
          resource={resource}
          refetch={refetch}
          confirmationEnabled={
            customResource ||
            resource.typeMeta.kind === Kind.CustomResourceDefinition ||
            resource.typeMeta.kind === Kind.Namespace
          }
          confirmationText={resource.objectMeta.name}
        />
      )}
    </div>
  )
}

enum DeletionPropagation {
  DeletePropagationBackground = 'Background',
  DeletePropagationForeground = 'Foreground',
  DeletePropagationOrphan = 'Orphan',
}

function toServerError(data: FetchResult): ServerError {
  const defaultError: ServerError = {
    statusCode: 500,
    result: 'Could not delete resource',
  } as ServerError

  if (!data.errors) {
    return defaultError
  }

  if (!((data.errors as unknown) instanceof ApolloError)) {
    return defaultError
  }

  const apolloError: ApolloError = data.errors as unknown as ApolloError
  const networkError: ServerError = apolloError?.networkError as ServerError

  return {
    statusCode: networkError?.statusCode,
    result: networkError?.result ?? networkError?.message,
  } as ServerError
}

interface DeleteResourceModalProps
  extends Pick<ConfirmProps, 'confirmationEnabled' | 'confirmationText'> {
  open: boolean
  setOpen: (open: boolean) => void
  resource: Resource
  refetch?: Nullable<LazyQueryExecFunction<any, any>>
}

function DeleteResourceModal({
  open,
  setOpen,
  resource,
  refetch,
  ...modalProps
}: DeleteResourceModalProps): ReactNode {
  const theme = useTheme()
  const [deleting, setDeleting] = useState(false)
  const [deleteNow, setDeleteNow] = useState(false)
  const [serverError, setServerError] = useState<ServerError>()
  const [propagation, setPropagation] = useState(
    DeletionPropagation.DeletePropagationBackground
  )
  const { clusterId } = useParams()
  const name = resource?.objectMeta?.name ?? ''
  const namespace = resource?.objectMeta?.namespace ?? ''
  const kind = resource?.typeMeta?.kind ?? ''
  const deleteDocument = useMemo(
    () =>
      namespace ? NamespacedResourceDeleteDocument : ResourceDeleteDocument,
    [namespace]
  )

  const [deleteResource, { error }] = useMutation(deleteDocument, {
    client: KubernetesClient(clusterId ?? ''),
    variables: {
      name,
      namespace,
      kind,
      propagation,
      deleteNow: `${deleteNow}`,
    },
    onError: () => setDeleting(false),
    onCompleted: () =>
      refetch
        ? refetch({
            context: {
              headers: {
                'Cache-Control': 'no-cache',
              },
            },
          })!
            .then(() => setOpen(false))
            .finally(() => setDeleting(false))
        : undefined,
  })

  return (
    <Confirm
      close={() => setOpen(false)}
      destructive
      label="Delete"
      loading={deleting}
      error={error}
      errorMessage={
        serverError?.result?.toString() ?? 'Could not delete resource'
      }
      errorHeader="Something went wrong"
      open={open}
      submit={() => {
        setDeleting(true)
        deleteResource().then((data) => setServerError(toServerError(data)))
      }}
      title={`Delete ${kind}`}
      text={`The ${kind} "${name}"${
        namespace ? ` in namespace "${namespace}"` : ''
      } will be deleted.`}
      extraContent={
        <div
          css={{
            paddingTop: theme.spacing.medium,
            display: 'flex',
            flexDirection: 'column',
            gap: theme.spacing.medium,
          }}
        >
          <FormField label="Propagation policy">
            <Select
              selectedKey={propagation}
              onSelectionChange={(key) =>
                setPropagation(key as DeletionPropagation)
              }
            >
              {Object.values(DeletionPropagation).map((d) => (
                <ListBoxItem
                  key={d}
                  label={d}
                />
              ))}
            </Select>
          </FormField>
          <Checkbox
            checked={deleteNow}
            onChange={(e) => setDeleteNow(e.target.checked)}
          >
            Delete now (sets delete grace period to 1 second)
          </Checkbox>
        </div>
      }
      {...modalProps}
    />
  )
}
