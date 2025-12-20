import { Aptos, AptosConfig, Network, Account, Ed25519PrivateKey, AddressInvalidReason } from "@aptos-labs/ts-sdk";
import dotenv from "dotenv";

dotenv.config();

//===CẤU HÌNH===

//1. Private key của Admin
const ADMIN_PRIVATE_KEY = process.env.VITE_MODULE_PUBLISHER_ACCOUNT_PRIVATE_KEY;
const MODULE_ADDRESS = process.env.VITE_MODULE_PUBLISHER_ACCOUNT_ADDRESS;

//2. Địa chỉ của FA đã tạo
const ASSET_METADATA_ADDRESS = "0x88ed75d06d6ad90173100c0e9997875bdfa904cea055aebb49b45bb00c9a75d9";

const args = process.argv.slice(2);
const inputAddress = args[0];
const inputAmount = args[1];

if (!inputAddress) {
  console.error("❌ Thiếu địa chỉ ví nhận!");
  process.exit(1);
}

const USER_ADDRESS = inputAddress;
const MINT_AMOUNT = inputAmount ? inputAmount : "100000000";

async function main() {
  const config = new AptosConfig({ network: Network.TESTNET });
  const aptos = new Aptos(config);

  try {
    if (!ADMIN_PRIVATE_KEY) throw new Error("Thiếu Admin Private Key trong .env");
    const adminAccount = Account.fromPrivateKey({
      privateKey: new Ed25519PrivateKey(ADMIN_PRIVATE_KEY),
    });
    console.log(`👑 Admin: ${adminAccount.accountAddress.toString()}`);
    console.log(`💵 Số lượng mint: ${MINT_AMOUNT}`);

    ///Gọi hàm public entry mint_to tự viết
    const transaction = await aptos.transaction.build.simple({
      sender: adminAccount.accountAddress,
      data: {
        ///Gọi hàm mint_to
        function: `${MODULE_ADDRESS}::ananta_token_project::mint_to`,
        functionArguments: [USER_ADDRESS, MINT_AMOUNT],
      },
    });

    const committedTxn = await aptos.signAndSubmitTransaction({
      signer: adminAccount,
      transaction: transaction,
    });
    console.log(`⌛ Tx Hash: ${committedTxn.hash}`);

    await aptos.waitForTransaction({ transactionHash: committedTxn.hash });

    console.log(`✅ Mint thành công!`);
  } catch (error) {
    console.error("Lỗi:", error);
  }
}

main();
