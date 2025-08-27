// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
// import {StdInvariant} from "forge-std/StdInvariant.sol";

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max; // the max uint96 value

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(weth)));
    }

    function mintDsc(uint256 amountDsc, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(sender);

        int256 maxDscToMint = (int256(collateralValueInUsd / 2) - int256(totalDscMinted));

        if (maxDscToMint <= 0) {
            return;
        }
        amountDsc = bound(amountDsc, 1, uint256(maxDscToMint));
        if (amountDsc == 0) {
            return;
        }

        vm.startPrank(sender);
        dscEngine.mintDsc(amountDsc);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        // pick the user (mirror mintDsc pattern) — ensures we redeem as someone who deposited
        if (usersWithCollateralDeposited.length == 0) return;
        address sender = usersWithCollateralDeposited[collateralSeed % usersWithCollateralDeposited.length];

        uint256 maxCollateralToRedeem = dscEngine.getCollateralBalanceOfUser(sender, address(collateral));
        if (maxCollateralToRedeem == 0) return;

        // info about the account
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(sender);

        // If user has minted DSC, compute how much USD-worth of collateral they can safely remove.
        // Requirement: totalDscMinted <= (collateralValueAfterRedeem / 2)
        // => collateralValueAfterRedeem >= 2 * totalDscMinted
        // => collateralValue - redeemUsd >= 2*totalDscMinted
        // => redeemUsd <= collateralValue - 2*totalDscMinted
        uint256 maxRedeemTokenBasedOnHealth = maxCollateralToRedeem; // default (if no DS C minted)
        if (totalDscMinted > 0) {
            // if collateralValueInUsd <= 2*totalDscMinted, then no redeem allowed
            if (collateralValueInUsd <= (2 * totalDscMinted)) {
                return;
            }

            uint256 maxRedeemUsd = collateralValueInUsd - (2 * totalDscMinted);

            // get USD value for 1e18 tokens (tokens use 18 decimals)
            uint256 usdPerWholeToken = dscEngine.getUsdValue(address(collateral), 1e18);
            // defensive: if price is zero, forbid redeem (avoid divide-by-zero)
            if (usdPerWholeToken == 0) return;

            // convert USD -> token units (1e18)
            uint256 maxRedeemTokensInWei = (maxRedeemUsd * 1e18) / usdPerWholeToken;

            // cap by their actual token balance
            if (maxRedeemTokensInWei < maxCollateralToRedeem) {
                maxRedeemTokenBasedOnHealth = maxRedeemTokensInWei;
            }
        }

        amountCollateral = bound(amountCollateral, 0, maxRedeemTokenBasedOnHealth);
        if (amountCollateral == 0) return;

        vm.startPrank(sender);
        dscEngine.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }
    // This breaks the invariant test suite!!!!!!
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    // Helper Functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
