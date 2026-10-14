import { Component } from 'react'
import Hud from './Hud'
import Cinematic from './Cinematic'
import Panel from './panel/Panel'

class Boundary extends Component {
  constructor(props) {
    super(props)
    this.state = { failed: false }
  }

  static getDerivedStateFromError() {
    return { failed: true }
  }

  componentDidCatch(error, info) {
    console.error(`[pr-adminjail] ${this.props.name} failed to render`, error, info)
  }

  render() {
    return this.state.failed ? null : this.props.children
  }
}

const SURFACES = [
  ['hud', Hud],
  ['cinematic', Cinematic],
  ['panel', Panel],
]

export default function App() {
  return (
    <>
      {SURFACES.map(([name, Surface]) => (
        <Boundary key={name} name={name}>
          <Surface />
        </Boundary>
      ))}
    </>
  )
}
