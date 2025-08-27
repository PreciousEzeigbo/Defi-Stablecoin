// SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig helperConfig;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = helperConfig.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }
    ////////////////////////////
    //   Constructor Tests   //
    ///////////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesNotMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /////////////////////
    //   Price Tests   //
    /////////////////////

    function testGetUsdValue() public {
        // Arrange
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18; // 15 ETH * $2000/ETH = $30,000

        // Act
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);

        // Assert
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedEth = 0.05 ether; // $100 / $2000 per ETH = 0.05 ETH
        uint256 actualEth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedEth, actualEth);
    }

    //////////////////////////////////
    //   Deposit Collateral Tests   //
    //////////////////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock();
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateral() public depositCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    ////////////////////////////////////////
    // NEW COMPREHENSIVE TESTS START HERE //
    ////////////////////////////////////////

    //////////////////////////////////
    //   Mint DSC Tests             //
    //////////////////////////////////

    function testRevertsIfMintAmountIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.mintDsc(0);
        vm.stopPrank();
    }

    function testRevertsIfMintAmountBreaksHealthFactor() public depositCollateral {
        (, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 amountDscToMint = collateralValueInUsd; // This would break health factor

        vm.startPrank(USER);
        uint256 expectedHealthFactor = dsce.calculateHealthFactor(amountDscToMint, collateralValueInUsd);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dsce.mintDsc(amountDscToMint);
        vm.stopPrank();
    }

    function testCanMintDsc() public depositCollateral {
        vm.startPrank(USER);
        dsce.mintDsc(AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, AMOUNT_COLLATERAL);
    }

    //////////////////////////////////
    //   Burn DSC Tests             //
    //////////////////////////////////

    function testRevertsIfBurnAmountIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.burnDsc(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanUserHas() public {
        vm.startPrank(USER);
        vm.expectRevert();
        dsce.burnDsc(1);
        vm.stopPrank();
    }

    function testCanBurnDsc() public depositCollateral {
        vm.startPrank(USER);
        dsce.mintDsc(AMOUNT_COLLATERAL);

        dsc.approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.burnDsc(AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    //////////////////////////////////
    //   Redeem Collateral Tests    //
    //////////////////////////////////

    function testRevertsIfRedeemAmountIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositCollateral {
        vm.startPrank(USER);
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 userBalance = ERC20Mock(weth).balanceOf(USER);
        assertEq(userBalance, STARTING_ERC20_BALANCE);
    }

    function testEmitCollateralRedeemedWithCorrectArgs() public depositCollateral {
        vm.expectEmit(true, true, true, true, address(dsce));
        emit CollateralRedeemed(USER, USER, weth, AMOUNT_COLLATERAL);

        vm.startPrank(USER);
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    //////////////////////////////////
    //  Redeem Collateral For DSC   //
    //////////////////////////////////

    function testMustRedeemMoreThanZero() public depositCollateral {
        vm.startPrank(USER);
        dsce.mintDsc(AMOUNT_COLLATERAL);
        dsc.approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateralForDsc(weth, 0, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanRedeemDepositedCollateralForDsc() public depositCollateral {
        vm.startPrank(USER);
        dsce.mintDsc(AMOUNT_COLLATERAL);
        dsc.approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);

        uint256 userWethBalance = ERC20Mock(weth).balanceOf(USER);
        assertEq(userWethBalance, STARTING_ERC20_BALANCE);
    }

    //////////////////////////////////
    //    Liquidation Tests         //
    //////////////////////////////////

    function testCantLiquidateGoodHealthFactor() public depositCollateral {
        ERC20Mock(weth).mint(address(this), STARTING_ERC20_BALANCE);
        ERC20Mock(weth).approve(address(dsce), type(uint256).max);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dsce.liquidate(weth, USER, AMOUNT_COLLATERAL);
    }

    modifier liquidated() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.mintDsc(AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    //////////////////////////////////
    //  depositCollateralAndMintDsc //
    //////////////////////////////////

    function testCanDepositCollateralAndMintDsc() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, AMOUNT_COLLATERAL);
    }

    //////////////////////////////////
    //    Health Factor Tests       //
    //////////////////////////////////

    function testProperlyReportsHealthFactor() public depositCollateral {
        vm.startPrank(USER);
        dsce.mintDsc(AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 expectedHealthFactor = 1000 ether; // 20,000 * 0.5 / 10 = 1000
        uint256 healthFactor = dsce.getHealthFactor(USER);
        // $10 DSC minted with $20,000 collateral at 50% liquidation threshold
        // means that we must have $20 collateral at all times.
        // 20,000 * 0.5 = 10,000
        // 10,000 / 10 = 1000 health factor
        assertEq(healthFactor, expectedHealthFactor);
    }

    function testHealthFactorCanGoBelowOne() public liquidated {
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        uint256 userHealthFactor = dsce.getHealthFactor(USER);
        // 180*50 (LIQUIDATION_THRESHOLD) / 100 (LIQUIDATION_PRECISION) / 10 (totalDscMinted) = 90 / 10 = 9
        // But with precision: 90e18 / 10e18 = 9e18
        assertEq(userHealthFactor, 9 ether);
    }

    //////////////////////////////////
    //   View & Pure Function Tests //
    //////////////////////////////////

    function testGetAccountCollateralValueFromInformation() public depositCollateral {
        (, uint256 collateralValue) = dsce.getAccountInformation(USER);
        uint256 expectedCollateralValue = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetCollateralBalanceOfUser() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 collateralBalance = dsce.getCollateralBalanceOfUser(USER, weth);
        assertEq(collateralBalance, AMOUNT_COLLATERAL);
    }

    function testGetAccountCollateralValue() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 collateralValue = dsce.getAccountCollateralValue(USER);
        uint256 expectedCollateralValue = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetMinHealthFactor() public {
        uint256 minHealthFactor = dsce.getMinHealthFactor();
        assertEq(minHealthFactor, 1e18);
    }

    function testGetLiquidationThreshold() public {
        uint256 liquidationThreshold = dsce.getLiquidationThreshold();
        assertEq(liquidationThreshold, 50);
    }

    function testGetLiquidationBonus() public {
        uint256 liquidationBonus = dsce.getLiquidationBonus();
        assertEq(liquidationBonus, 10);
    }

    function testGetLiquidationPrecision() public {
        uint256 liquidationPrecision = dsce.getLiquidationPrecision();
        assertEq(liquidationPrecision, 100);
    }

    function testGetCollateralTokens() public {
        address[] memory collateralTokens = dsce.getCollateralTokens();
        assertEq(collateralTokens[0], weth);
    }

    function testGetDsc() public {
        address dscAddress = dsce.getDsc();
        assertEq(dscAddress, address(dsc));
    }

    function testGetCollateralTokenPriceFeed() public {
        address priceFeed = dsce.getCollateralTokenPriceFeed(weth);
        assertEq(priceFeed, ethUsdPriceFeed);
    }

    function testGetAdditionalFeedPrecision() public {
        uint256 additionalFeedPrecision = dsce.getAdditionalFeedPrecision();
        assertEq(additionalFeedPrecision, 1e10);
    }

    function testGetPrecision() public {
        uint256 precision = dsce.getPrecision();
        assertEq(precision, 1e18);
    }

    //////////////////////////////////
    //    Edge Case Tests           //
    //////////////////////////////////

    function testHealthFactorReturnsMaxForZeroDscMinted() public depositCollateral {
        uint256 healthFactor = dsce.getHealthFactor(USER);
        assertEq(healthFactor, type(uint256).max);
    }

    function testCanDepositZeroCollateralWithZeroDscMinted() public {
        uint256 healthFactor = dsce.getHealthFactor(USER);
        assertEq(healthFactor, type(uint256).max);
    }

    //////////////////////////////////
    //    Integration Tests         //
    //////////////////////////////////

    function testMultipleUsersCanDepositCollateralAndMintDsc() public {
        address user2 = makeAddr("user2");
        ERC20Mock(weth).mint(user2, STARTING_ERC20_BALANCE);

        // User 1
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_COLLATERAL);
        vm.stopPrank();

        // User 2
        vm.startPrank(user2);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 user1Balance = dsc.balanceOf(USER);
        uint256 user2Balance = dsc.balanceOf(user2);

        assertEq(user1Balance, AMOUNT_COLLATERAL);
        assertEq(user2Balance, AMOUNT_COLLATERAL);
    }

    function testUserCanBurnAllDscAndRedeemAllCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_COLLATERAL);

        dsc.approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 userDscBalance = dsc.balanceOf(USER);
        uint256 userWethBalance = ERC20Mock(weth).balanceOf(USER);
        uint256 userCollateralDeposited = dsce.getCollateralBalanceOfUser(USER, weth);

        assertEq(userDscBalance, 0);
        assertEq(userWethBalance, STARTING_ERC20_BALANCE);
        assertEq(userCollateralDeposited, 0);
    }

    // Events to match DSCEngine events
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );
}
