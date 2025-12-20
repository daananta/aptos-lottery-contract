import { Aptos, AptosConfig, Network, Account, Ed25519PrivateKey } from "@aptos-labs/ts-sdk";
import dotenv from "dotenv";
dotenv.config();
// --- CẤU HÌNH ---

// 1. Chọn mạng (DEVNET, TESTNET, hoặc MAINNET)
const APTOS_NETWORK: Network = Network.TESTNET;

// 2. Địa chỉ của Module (Địa chỉ ví đã deploy contract)
// Đây là giá trị thay thế cho @my_addr trong file Move
const MY_ADDR_ADDRESS = process.env.VITE_MODULE_PUBLISHER_ACCOUNT_ADDRESS;

// 3. Private Key của người mua vé (User)
// Lưu ý: Trong thực tế nên để trong file .env, không được hardcode
const USER_PRIVATE_KEY = process.env.VITE_MODULE_PUBLISHER_ACCOUNT_PRIVATE_KEY;

// 🛠️ SỬA PHẦN NÀY:
// Lấy tham số thứ 3 từ dòng lệnh (index 2 vì 0 là node, 1 là tên file)
const args = process.argv.slice(2);
const inputAmount = args[0];

// Nếu có nhập số thì dùng số đó, nếu không nhập thì mặc định mua 1 vé
const TICKET_AMOUNT = inputAmount ? parseInt(inputAmount) : 1;

// Kiểm tra cho chắc chắn là số
if (isNaN(TICKET_AMOUNT) || TICKET_AMOUNT <= 0) {
  throw new Error("❌ Vui lòng nhập số lượng vé hợp lệ (ví dụ: 5)");
}

async function main() {
  // Khởi tạo kết nối Aptos
  const config = new AptosConfig({ network: APTOS_NETWORK });
  const aptos = new Aptos(config);

  try {
    // Khôi phục tài khoản từ Private Key
    const privateKey = new Ed25519PrivateKey(USER_PRIVATE_KEY!);
    const userAccount = Account.fromPrivateKey({ privateKey });

    console.log(`User Address: ${userAccount.accountAddress.toString()}`);
    console.log(`Đang mua ${TICKET_AMOUNT} vé...`);

    // Xây dựng transaction gọi hàm buy_ticket
    const transaction = await aptos.transaction.build.simple({
      sender: userAccount.accountAddress,
      data: {
        // Cấu trúc: address::module_name::function_name
        function: `${MY_ADDR_ADDRESS}::lottery::buy_ticket`,
        // Tham số truyền vào: [amount: u64]
        functionArguments: [TICKET_AMOUNT],
      },
    });

    // Ký và gửi transaction lên mạng
    const committedTxn = await aptos.signAndSubmitTransaction({
      signer: userAccount,
      transaction: transaction,
    });

    console.log(`Transaction submitted. Hash: ${committedTxn.hash}`);
    console.log("Đang chờ xác nhận...");

    // Chờ transaction được thực thi xong
    const response = await aptos.waitForTransaction({
      transactionHash: committedTxn.hash,
    });

    // Kiểm tra kết quả
    if (response.success) {
      console.log("✅ Mua vé thành công!");
      console.log(`Xem chi tiết tại: https://explorer.aptoslabs.com/txn/${committedTxn.hash}?network=${APTOS_NETWORK}`);
    } else {
      console.error("❌ Transaction thất bại.");
    }
  } catch (error: any) {
    console.error("Gặp lỗi:", error);
  }
}

main();
