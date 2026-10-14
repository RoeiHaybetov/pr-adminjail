import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'

import '@fontsource/lexend/400.css'
import '@fontsource/lexend/500.css'
import '@fontsource/lexend/600.css'
import '@fontsource/lexend/700.css'
import '@fontsource/lexend/800.css'
import '@fontsource/jetbrains-mono/400.css'
import './styles.css'

import App from './App'
import { isBrowser } from './lib'

if (isBrowser) {
  document.body.classList.add('browser')
  if (import.meta.env.DEV) import('./mock')
}

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
