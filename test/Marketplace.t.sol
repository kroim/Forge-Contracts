// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Marketplace, IERC721, IERC721, Address} from "../src/Marketplace.sol";
import {Collection} from "../src/Collection.sol";

contract MarketplaceTest is Test {
    Marketplace marketplace;
    Collection collection;

    address public constant OWNER = address(123456789);
    address public constant buyer = address(123);
    address public constant seller = address(456);
    uint256 startTimestamp = 1617580800;
    uint256 public constant initValue = 10 ** 20;  // 20 ETH

    function setUp() public {
        vm.warp(startTimestamp);
        startHoax(OWNER, OWNER, 0);
        marketplace = new Marketplace();
        marketplace.registration("Owner");
        vm.stopPrank();
        assert(OWNER == marketplace.owner());

        startHoax(seller, seller, 0);
        marketplace.registration("Seller");
        vm.stopPrank();

        startHoax(buyer, buyer, initValue);
        marketplace.registration("Buyer");
        vm.stopPrank();

        collection = new Collection("Test NFT", "Test");
        collection.mint(seller, 1);
        collection.mint(seller, 2);
        assert(collection.ownerOf(1) == seller);
        assert(collection.ownerOf(2) == seller);
    }

    function utils_list(uint256 tokenId, uint256 amount) public {
        startHoax(seller, seller, 0);
        collection.approve(address(marketplace), tokenId);
        marketplace.list(address(collection), tokenId, amount);
        vm.stopPrank();
    }

    function utils_delist(uint256 orderId) public {
        startHoax(seller, seller, 0);
        marketplace.delist(orderId);
        vm.stopPrank();
    }

    function utils_purchase(uint256 orderId, uint256 amount) public {
        startHoax(buyer, buyer, type(uint256).max);
        marketplace.buy{value: amount}(orderId);
        vm.stopPrank();
    }

    function testMarketplace() public {
        // listing on marketplace with price
        uint256 amount1 = 10 ** 17;  // 0.1 ETH
        uint256 amount2 = 2 * 10 ** 17;  // 0.2 ETH
        utils_list(1, amount1);
        assert(marketplace.orderIndex() == 1);
        assert(collection.ownerOf(1) == address(marketplace));
        console.log("Listed tokenId 1 on the marketplace");
        utils_list(2, amount2);
        assert(marketplace.orderIndex() == 2);
        assert(collection.ownerOf(2) == address(marketplace));
        console.log("Listed tokenId 2 on the marketplace");

        // delisting
        utils_delist(1);
        assert(marketplace.getOrder(1).status == false);
        assert(collection.ownerOf(1) == seller);
        console.log("DeListed tokenId 2 on the marketplace");
        // Buy NFT
        utils_purchase(2, amount2);
        assert(collection.ownerOf(2) == buyer);
        console.log("Purchased NFT");

        // Print Order Info, History
        console.log("--- Order Info ---");
        Marketplace.Order memory order1 = marketplace.getOrder(1);
        console.log("OrderId: ", order1.id);
        console.log("TokenId: ", order1.tokenId);
        console.log("OrderPrice: ", order1.price);
        console.log("OrderStatus: ", order1.status);

        Marketplace.Order memory order2 = marketplace.getOrder(2);
        console.log("OrderId: ", order2.id);
        console.log("TokenId: ", order2.tokenId);
        console.log("OrderPrice: ", order2.price);
        console.log("OrderStatus: ", order2.status);

        console.log("--- History for seller ---");
        Marketplace.History[] memory s_histories = marketplace.getHistory(seller);
        uint256 s_historyLength = s_histories.length;
        console.log("History Length: ", s_historyLength);
        for (uint256 i = 0; i < s_historyLength; i++) {
            Marketplace.History memory history = s_histories[i];
            console.log("%d - History Index", i);
            console.log("Time: ", history.timestamp);
            console.log("Action: ", history.action);
            console.log("OrderId: ", history.order.id);
        }
        console.log("--- History for buyer ---");
        Marketplace.History[] memory b_histories = marketplace.getHistory(buyer);
        uint256 b_historyLength = b_histories.length;
        console.log("History Length: ", b_historyLength);
        for (uint256 i = 0; i < b_historyLength; i++) {
            Marketplace.History memory history = b_histories[i];
            console.log("%d - History Index", i);
            console.log("Time: ", history.timestamp);
            console.log("Action: ", history.action);
            console.log("OrderId: ", history.order.id);
        }
    }
}