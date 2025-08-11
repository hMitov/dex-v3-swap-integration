// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import "./interfaces/ITWAPPriceProvider.sol";
import "./interfaces/ITokenMetadata.sol";

/**
 * @title TWAPPriceProvider
 * @dev A contract that provides TWAP prices from Uniswap V3 pools for predefined token pairs
 * Self-contained implementation without external libraries
 */
contract TWAPPriceProvider is ITWAPPriceProvider, AccessControl, ReentrancyGuard, Pausable {
    // Mapping from pair ID to TokenPair info
    mapping(bytes32 => TokenPair) public tokenPairs;

    /// @notice Default TWAP period in seconds (15 minutes)
    uint32 public override defaultTwapPeriod = 900;

    /// @notice Maximum allowed TWAP period in seconds (24 hours)
    uint32 public constant MAX_TWAP_PERIOD = 86400;

    /// @notice Role identifier for admin operations
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Role identifier for pausing operations
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    constructor() {
        address deployer = msg.sender;

        _setupRole(DEFAULT_ADMIN_ROLE, deployer);
        _setupRole(ADMIN_ROLE, deployer);
        _setupRole(PAUSER_ROLE, deployer);

        _setRoleAdmin(PAUSER_ROLE, ADMIN_ROLE);
    }

    /**
     * @notice Modifier that restricts access to admin accounts only
     * @dev Reverts if the caller does not have ADMIN_ROLE
     */
    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not admin");
        _;
    }

    /**
     * @notice Modifier that restricts access to pauser accounts only
     * @dev Reverts if the caller does not have PAUSER_ROLE
     */
    modifier onlyPauser() {
        require(hasRole(PAUSER_ROLE, msg.sender), "Caller is not pauser");
        _;
    }

    /**
     * @notice Pauses the contract, disabling all price fetching operations
     * @dev Only callable by accounts with PAUSER_ROLE
     */
    function pause() external override onlyPauser {
        _pause();
    }

    /**
     * @notice Unpauses the contract, re-enabling all price fetching operations
     * @dev Only callable by accounts with PAUSER_ROLE
     */
    function unpause() external override onlyPauser {
        _unpause();
    }

    /**
     * @notice Grants the pauser role to a specified account
     * @dev Only callable by accounts with ADMIN_ROLE
     * @dev Reverts if the account address is zero
     *
     * @param _account The address to grant the pauser role to
     */
    function grantPauserRole(address _account) external override onlyAdmin {
        require(_account != address(0), "Zero address not allowed");
        grantRole(PAUSER_ROLE, _account);
    }

    /**
     * @notice Revokes the pauser role from a specified account
     * @dev Only callable by accounts with ADMIN_ROLE
     * @dev Reverts if the account address is zero
     *
     * @param _account The address to revoke the pauser role from
     */
    function revokePauserRole(address _account) external override onlyAdmin {
        require(_account != address(0), "Zero address not allowed");
        revokeRole(PAUSER_ROLE, _account);
    }

    /**
     * @dev Add a new token pair for price fetching
     * @param _token0 Address of the first token
     * @param _token1 Address of the second token
     * @param _pool Address of the Uniswap V3 pool
     * @param _fee Fee tier of the pool
     */
    function addTokenPair(address _token0, address _token1, address _pool, uint24 _fee) external override onlyAdmin {
        require(_token0 != address(0) && _token1 != address(0) && _pool != address(0), "Invalid tokens");
        require(_token0 != _token1, "Tokens must differ");

        bytes32 pairId = _getPairId(_token0, _token1, _fee);
        require(!tokenPairs[pairId].isActive, "Pair already exists");

        // Verify the pool exists and has the correct tokens
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);
        require(pool.token0() == _token0 && pool.token1() == _token1 && pool.fee() == _fee, "Invalid pool");

        tokenPairs[pairId] = TokenPair({token0: _token0, token1: _token1, pool: _pool, fee: _fee, isActive: true});

        emit PairAdded(pairId, _token0, _token1, _pool, _fee);
    }

    /**
     * @notice Removes a token pair from the supported pairs list
     * @dev Remove a token pair
     * @param _token0 Address of the first token
     * @param _token1 Address of the second token
     * @param _fee Fee tier of the pool
     */
    function removeTokenPair(address _token0, address _token1, uint24 _fee) external override onlyAdmin {
        bytes32 pairId = _getPairId(_token0, _token1, _fee);
        require(tokenPairs[pairId].isActive, "Pair not found");

        tokenPairs[pairId].isActive = false;

        emit PairRemoved(pairId);
    }

    /**
     * @notice Gets the TWAP price for a token pair with proper denomination handling
     * @param _tokenIn Address of the input token (base asset)
     * @param _tokenOut Address of the output token (quote asset)
     * @param _amountIn Amount of input token (in base asset's decimals)
     * @param _fee Fee tier of the pool to use for price calculation
     * @param _twapPeriod TWAP period in seconds (15 minutes for default period)
     *
     * @return amountOut Price of base asset denominated in quote asset
     * @return decimalsOut Decimals of the quote asset for proper formatting
     */
    function getTwapPrice(address _tokenIn, address _tokenOut, uint128 _amountIn, uint24 _fee, uint32 _twapPeriod)
        external
        view
        override
        returns (uint256 amountOut, uint8 decimalsOut)
    {
        require(_tokenIn != address(0) && _tokenOut != address(0), "Zero token");
        require(_tokenIn != _tokenOut, "Same token");
        require(_amountIn > 0, "Invalid amountIn");

        uint32 period = _twapPeriod == 0 ? defaultTwapPeriod : _twapPeriod;
        require(period > 0 && period <= MAX_TWAP_PERIOD, "Invalid TWAP period");

        // Load pair once
        bytes32 pairId = _getPairId(_tokenIn, _tokenOut, _fee);
        TokenPair memory pair = tokenPairs[pairId];
        require(pair.isActive, "Pair not found");

        IUniswapV3Pool pool = IUniswapV3Pool(pair.pool);

        (int24 meanTick,) = OracleLibrary.consult(address(pool), period);

        amountOut = OracleLibrary.getQuoteAtTick(meanTick, _amountIn, _tokenIn, _tokenOut);
        // Get decimals for proper denomination display
        decimalsOut = ITokenMetadata(_tokenOut).decimals();
    }

    /**
     * @notice Checks if a token pair is supported for price fetching
     * @dev This function is view-only and does not modify state
     * @dev Returns true if the pair exists and is active
     *
     * @param _tokenA Address of the first token
     * @param _tokenB Address of the second token
     * @param _fee Fee tier of the pool
     *
     * @return isSupported Whether the pair is supported and active
     */
    function isPairSupported(address _tokenA, address _tokenB, uint24 _fee)
        external
        view
        override
        returns (bool isSupported)
    {
        bytes32 pairId = _getPairId(_tokenA, _tokenB, _fee);
        return tokenPairs[pairId].isActive;
    }

    /**
     * @notice Generates a unique pair ID from tokens and fee tier
     * @dev This function is internal and pure (no state changes or external calls)
     *
     * @param _tokenA First token address
     * @param _tokenB Second token address
     * @param _fee Fee tier of the pool
     *
     * @return pairId Unique identifier for the token pair and fee combination
     */
    function _getPairId(address _tokenA, address _tokenB, uint24 _fee) internal pure returns (bytes32 pairId) {
        // Ensure consistent ordering
        if (_tokenA > _tokenB) {
            (_tokenA, _tokenB) = (_tokenB, _tokenA);
        }
        return keccak256(abi.encodePacked(_tokenA, _tokenB, _fee));
    }
}
