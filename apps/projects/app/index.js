import './utils/devTooling'
import React from 'react'
import ReactDOM from '@hot-loader/react-dom'
import Aragon, { providers } from '@aragon/api'
import App from './components/App/App'

// import { projectsMockData } from './utils/mockData'

// TODO: Convert to stateless functional component
class ConnectedApp extends React.Component {
  constructor(props) {
    super(props)
    this.state = {
      app: new Aragon(new providers.WindowMessage(window.parent)),
      network: {},
      observable: null,
      userAccount: '',
    }
  }

  componentDidMount() {
    window.addEventListener('message', this.handleWrapperMessage)
  }
  componentWillUnmount() {
    window.removeEventListener('message', this.handleWrapperMessage)
  }
  // handshake between Aragon Core and the iframe,
  // since iframes can lose messages that were sent before they were ready
  handleWrapperMessage = ({ data }) => {
    const { app } = this.state
    if (data.from !== 'wrapper') {
      return
    }
    if (data.name === 'ready') {
      this.sendMessageToWrapper('ready', true)
      this.setState({
        observable: app.state(),
      })
      app.accounts().subscribe(accounts => {
        this.setState({ userAccount: accounts[0] || '' })
      })
      app.network().subscribe(network => {
        this.setState({ network })
      })
    }
  }
  sendMessageToWrapper = (name, value) => {
    window.parent.postMessage({ from: 'app', name, value }, '*')
  }
  render() {
    return <App {...this.state} />
  }
}
// module.hot.accept(
ReactDOM.render(<ConnectedApp />, document.getElementById('projects'))
// )
