import React from 'react'
import PropTypes from 'prop-types'

import { BoxContext } from '.'
import { use3Box } from '../../hooks'

const BoxWrapper = ({ children }) => {
  const { boxes, dispatch } = use3Box()
  return (
    <BoxContext.Provider value={{ boxes, dispatch }}>
      {children}
    </BoxContext.Provider>
  )
}

BoxWrapper.propTypes = {
  children: PropTypes.node.isRequired,
}

export default BoxWrapper
