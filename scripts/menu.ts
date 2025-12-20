import inquirer from "inquirer";
import { execSync } from "child_process";

const main = async () => {
  console.clear();
  console.log("\n🎲 --- APTOS LOTTERY MANAGER --- 🎲\n");

  const answer = await inquirer.prompt([
    {
      type: "list",
      name: "action",
      message: "Bạn muốn làm gì?",
      choices: [
        { name: "🚀 1. Khởi tạo Token & Mint (Init & Mint)", value: "1_init_and_mint.ts" },
        { name: "🎟️  2. Mua vé số (Buy Ticket)", value: "2_buy_ticket.ts" },
        { name: "🏆 3. Chọn người trúng (Pick Winner)", value: "3_pick_winner.ts" },
        // 👇 1. THÊM LỰA CHỌN MỚI Ở ĐÂY
        { name: "💰 4. Mint Token cho User", value: "4_mint_token_to_user.ts" },
        new inquirer.Separator(),
        { name: "❌ Thoát", value: "exit" },
      ],
    },
  ]);

  if (answer.action === "exit") {
    console.log("Tạm biệt!");
    process.exit(0);
  }

  // Biến lưu các tham số sẽ truyền vào command
  let args = "";

  // --- XỬ LÝ RIÊNG CHO TỪNG FILE ---

  // Trường hợp 1: Mua vé (Hỏi số lượng vé)
  if (answer.action === "2_buy_ticket.ts") {
    const ticketAnswer = await inquirer.prompt([
      {
        type: "input",
        name: "amount",
        message: "Bạn muốn mua bao nhiêu vé?",
        default: "1",
        validate: (input) => {
          const num = parseInt(input);
          if (isNaN(num) || num <= 0) return "Vui lòng nhập số dương!";
          return true;
        },
      },
    ]);
    args = ` ${ticketAnswer.amount}`;
  }

  // 👇 2. THÊM LOGIC HỎI THÔNG TIN CHO FILE MINT
  else if (answer.action === "4_mint_token_to_user.ts") {
    const mintAnswers = await inquirer.prompt([
      {
        type: "input",
        name: "address",
        message: "Nhập địa chỉ ví nhận tiền (0x...):",
        validate: (input) => {
          if (!input.startsWith("0x") || input.length < 60) {
            return "Địa chỉ ví có vẻ không hợp lệ (Phải bắt đầu bằng 0x và đủ dài)";
          }
          return true;
        },
      },
      {
        type: "input",
        name: "amount",
        message: "Nhập số lượng Token muốn mint:",
        default: "100000000", // Mặc định 100 triệu
        validate: (input) => {
          if (isNaN(parseInt(input))) return "Vui lòng nhập số!";
          return true;
        },
      },
    ]);

    // Tạo chuỗi tham số: " <địa_chỉ> <số_lượng>"
    // Ví dụ: " 0x123... 5000"
    args = ` ${mintAnswers.address} ${mintAnswers.amount}`;
  }

  // --- CHẠY LỆNH ---
  try {
    console.log(`\n⏳ Đang chạy: ${answer.action}...\n`);

    // Lệnh thực thi: npx ts-node scripts/ten_file.ts [param1] [param2]
    execSync(`npx ts-node scripts/${answer.action}${args}`, { stdio: "inherit" });

    console.log("\n✅ Lệnh đã chạy xong!");
  } catch (error) {
    console.log("\n❌ Script dừng hoặc có lỗi (Kiểm tra lại code nhé).");
  }
};

main();
