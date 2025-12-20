import { useWallet } from "@aptos-labs/wallet-adapter-react";
// Internal Components
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Header } from "@/components/Header";
import { WalletDetails } from "@/components/WalletDetails";
import { NetworkInfo } from "@/components/NetworkInfo";
import { AccountInfo } from "@/components/AccountInfo";
import { TopBanner } from "@/components/TopBanner";
import { LotteryBoard } from "@/components/LotteryBoard"; 

function App() {
  const { connected } = useWallet();

  return (
    <>
     
      {/* Thêm padding-bottom và background nhẹ nếu muốn */}
      <div className="min-h-screen flex items-center justify-start flex-col pb-20 px-4">
        {connected ? (
          <div className="flex flex-col items-center w-full gap-8">
            
            {/* Phần hiển thị Game Xổ Số - Đưa lên đầu cho nổi bật */}
            <LotteryBoard />

            {/* Phần thông tin ví - Để xuống dưới dưới dạng Cards phụ */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6 w-full max-w-4xl">
              <Card>
                 <CardHeader><CardTitle>Ví Của Bạn</CardTitle></CardHeader>
                 <CardContent><WalletDetails /></CardContent>
              </Card>
              <Card>
                 <CardHeader><CardTitle>Thông Tin Mạng</CardTitle></CardHeader>
                 <CardContent className="pt-6"><NetworkInfo /></CardContent>
              </Card>
              <Card className="md:col-span-2">
                 <CardHeader><CardTitle>Tài Khoản</CardTitle></CardHeader>
                 <CardContent className="pt-6"><AccountInfo /></CardContent>
              </Card>
            </div>
            
          </div>
        ) : (
          <CardHeader>
            <CardTitle>Vui lòng kết nối ví để bắt đầu</CardTitle>
          </CardHeader>
        )}
      </div>
    </>
  );
}

export default App;