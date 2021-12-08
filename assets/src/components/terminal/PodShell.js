import React, { useContext, useEffect } from 'react'
import { useParams } from 'react-router'
import { BreadcrumbsContext } from '../Breadcrumbs'
import { Shell } from './Shell'

export function PodShell() {
  const {namespace, name, container} = useParams()
  const {setBreadcrumbs} = useContext(BreadcrumbsContext)

  useEffect(() => {
    setBreadcrumbs([
      {text: 'pods', url: `/components/${namespace}`},
      {text: namespace, url: `/components/${namespace}`},
      {text: name, url: `/pods/${namespace}/${name}`},
      {text: container, url: `/shell/pod/${namespace}/${name}/${container}`}
    ])
  }, [namespace, name, container])

  return (
    <Shell 
      room={`pod:${namespace}:${name}:${container}`} 
      header={`Shelling into pod ${name}:${container}...`} />
  )
}