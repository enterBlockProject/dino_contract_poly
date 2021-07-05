// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IController {
    function refreshOwner(address,address,uint) external;
}