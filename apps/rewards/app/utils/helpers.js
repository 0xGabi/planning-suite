import { ETH_DECIMALS } from './constants'
import BigNumber from 'bignumber.js'
export const isNumberString = value => /^\d+(\.\d+)?$/.test(value)
export const isStringEmpty = string => string.length === 0
export const displayCurrency = amount => {
  return BigNumber(amount).div(ETH_DECIMALS).dp(3).toString()
  //return BN(amount).dp(3).toString()
}

export const toCurrency = (amount, decimals) => {
  return BigNumber(amount).times(BigNumber(10).pow(decimals)).toString()
}

export const getSymbol = (tokens, rewardToken) => {
  return tokens
    .reduce((symbol, token) => {
      if (token.address === rewardToken) return token.symbol
      else return symbol
    },'')
}
