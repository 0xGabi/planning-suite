import { app } from '../app'
import tokenSymbolAbi from '../../abi/token-symbol.json'
import tokenDecimalsAbi from '../../abi/token-decimal.json'

const tokenAbi = [].concat(tokenDecimalsAbi, tokenSymbolAbi)

const loadTokenBalance = (tokenAddress, vaultContract) => {
  return vaultContract.balance(tokenAddress).toPromise()
}

const loadToken = async (tokenAddress, vaultContract) => {
  const tokenContract = app.external(tokenAddress, tokenAbi)

  const [ balance, decimals, symbol ] = await Promise.all([
    loadTokenBalance(tokenAddress, vaultContract),
    tokenContract.decimals().toPromise(),
    tokenContract.symbol().toPromise(),
  ])

  return ({
    addr: tokenAddress,
    symbol: symbol,
    decimals: decimals,
    balance: balance,
  })
}

export const syncTokens = async (state, { token }, vaultContract) => {
  try {
    const tokens = state.tokens
    let tokenIndex = tokens.findIndex(currentToken => currentToken.addr === token)
    if(tokenIndex == -1) {
      let newToken = await loadToken(token, vaultContract)
      tokenIndex = tokens.findIndex(currentToken => currentToken.symbol === newToken.symbol)
      if(tokenIndex !== -1) {
        tokens[tokenIndex] = newToken
      }
      else {
        tokens.push(newToken)
      }
    }

    else {
      tokens[tokenIndex].balance = await loadTokenBalance(token, vaultContract)
    }
    return state
  } catch (err) {
    console.error('[Projects script] syncSettings settings failed:', err)
    return state
  }
}
