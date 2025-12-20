import { useEffect, useState } from "react";
import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Ticket, Clock, Trophy, Minus, Plus, RefreshCw, Sparkles, Coins } from "lucide-react";

// Internal imports
import { toast } from "@/components/ui/use-toast";
import { aptosClient } from "@/utils/aptosClient";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { MODULE_ADDRESS } from "@/constants";

// 1. Cập nhật Type để lấy thêm thông tin asset_metadata
type LotteryGameResource = {
  price_ticket: string;
  prize_pool: string;
  players: { data: Array<any> };
  epoch: string;
  last_time: string;
  asset_metadata: { inner: string }; // Lấy địa chỉ của Token (ANANTA)
};

export function LotteryBoard() {
  const { account, signAndSubmitTransaction } = useWallet();
  const queryClient = useQueryClient();
  const [ticketAmount, setTicketAmount] = useState<number>(1);
  const [timeLeft, setTimeLeft] = useState<string>("Loading...");
  const [isBuying, setIsBuying] = useState(false);

  // 1. Fetch Data Game
  const { data: gameData, refetch } = useQuery({
    queryKey: ["lottery-data"],
    refetchInterval: 5000,
    queryFn: async () => {
      try {
        const payload = {
          function: `${MODULE_ADDRESS}::lottery::get_game_address` as `${string}::${string}::${string}`,
          functionArguments: [MODULE_ADDRESS],
        };
        const res = await aptosClient().view({ payload });
        const gameAddress = res[0] as string;

        const resource = await aptosClient().getAccountResource({
          accountAddress: gameAddress,
          resourceType: `${MODULE_ADDRESS}::lottery::LotteryGame`,
        });
        return resource as unknown as LotteryGameResource;
      } catch (error) {
        console.error("Error fetching game data", error);
        return null;
      }
    },
  });

  // 2. Fetch User ANANTA Balance (Tính năng mới)
  const { data: userBalance } = useQuery({
    queryKey: ["ananta-balance", account?.address, gameData?.asset_metadata],
    enabled: !!account && !!gameData, // Chỉ chạy khi đã kết nối ví và load xong game
    refetchInterval: 5000,
    queryFn: async () => {
        if (!account || !gameData) return "0";
        try {
            const res = await aptosClient().view({
                payload: {
                    function: "0x1::primary_fungible_store::balance",
                    typeArguments: ["0x1::fungible_asset::Metadata"], // Metadata Type
                    functionArguments: [account.address, gameData.asset_metadata.inner]
                }
            });
            return res[0] as string;
        } catch (e) {
            return "0";
        }
    }
  });

  // 3. Logic Countdown
  useEffect(() => {
    if (!gameData) return;
    const interval = setInterval(() => {
      const now = Math.floor(Date.now() / 1000);
      const endTime = parseInt(gameData.last_time) + parseInt(gameData.epoch);
      const diff = endTime - now;

      if (diff <= 0) {
        setTimeLeft("Sắp quay thưởng!");
      } else {
        const minutes = Math.floor(diff / 60);
        const seconds = diff % 60;
        setTimeLeft(`${minutes}p ${seconds}s`);
      }
    }, 1000);
    return () => clearInterval(interval);
  }, [gameData]);

  // 4. Hàm Mua Vé
  const onBuyTicket = async () => {
    if (!account) return;
    setIsBuying(true);
    try {
      const response = await signAndSubmitTransaction({
        sender: account.address,
        data: {
          function: `${MODULE_ADDRESS}::lottery::buy_ticket`,
          functionArguments: [ticketAmount],
        },
      });
      await aptosClient().waitForTransaction({ transactionHash: response.hash });
      toast({
        title: "🎉 Mua vé thành công!",
        description: `Chúc bạn may mắn! Hash: ${response.hash.slice(0, 6)}...`,
        duration: 5000,
        className: "bg-green-600 text-white border-none",
      });
      refetch(); // Load lại data ngay
    } catch (error: any) {
      toast({
        variant: "destructive",
        title: "Thất bại",
        description: error.message || "Giao dịch bị hủy",
      });
    } finally {
      setIsBuying(false);
    }
  };

  // --- HÀM FORMAT TIỀN MỚI ---
  // Chia cho 10^6 (thay vì 10^8) và thêm đuôi ANANTA
  const formatToken = (val: string) => {
      const amount = Number(val) / 1000000; // Decimals = 6
      return amount.toLocaleString("en-US", { maximumFractionDigits: 2 });
  }

  return (
    <Card className="w-full max-w-lg mt-8 border-none shadow-2xl bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 text-white overflow-hidden relative">
      <div className="absolute top-0 left-0 w-full h-2 bg-gradient-to-r from-cyan-500 via-blue-500 to-indigo-500 animate-pulse" />
      
      <CardHeader className="text-center space-y-2 pb-2">
        <div className="flex justify-center mb-2">
           <div className="p-3 bg-white/10 rounded-full animate-bounce duration-3000">
             <Trophy className="w-8 h-8 text-cyan-400" />
           </div>
        </div>
        <CardTitle className="text-3xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-cyan-200 to-blue-500">
          ANANTA LOTTERY
        </CardTitle>
        <CardDescription className="text-slate-400">
          Xổ số Fungible Asset thế hệ mới
        </CardDescription>
      </CardHeader>

      <CardContent className="flex flex-col gap-6 pt-4">
        {/* Prize Pool Section */}
        <div className="relative group">
            <div className="absolute -inset-0.5 bg-gradient-to-r from-cyan-600 to-blue-600 rounded-xl blur opacity-75 group-hover:opacity-100 transition duration-1000 group-hover:duration-200 animate-tilt"></div>
            <div className="relative p-6 bg-slate-900 rounded-xl border border-white/10 flex flex-col items-center">
                <span className="text-slate-400 font-medium uppercase tracking-wider text-xs flex items-center gap-2">
                    <Sparkles className="w-3 h-3 text-cyan-400" /> Tổng Giải Thưởng
                </span>
                <span className="text-5xl font-black text-white mt-2 drop-shadow-[0_0_15px_rgba(34,211,238,0.5)]">
                    {gameData ? formatToken(gameData.prize_pool) : "0"} <span className="text-2xl text-cyan-400">ANANTA</span>
                </span>
            </div>
        </div>

        {/* Info Grid */}
        <div className="grid grid-cols-2 gap-4">
            <div className="bg-white/5 p-4 rounded-lg flex flex-col items-center border border-white/5 hover:bg-white/10 transition-colors">
                <span className="text-slate-400 text-xs mb-1 flex items-center gap-1">
                    <Clock className="w-3 h-3" /> Quay thưởng sau
                </span>
                <span className="text-xl font-bold text-green-400 font-mono">{timeLeft}</span>
            </div>
            <div className="bg-white/5 p-4 rounded-lg flex flex-col items-center border border-white/5 hover:bg-white/10 transition-colors">
                <span className="text-slate-400 text-xs mb-1 flex items-center gap-1">
                    <Ticket className="w-3 h-3" /> Giá vé
                </span>
                <span className="text-xl font-bold text-blue-400">
                    {gameData ? formatToken(gameData.price_ticket) : "0"} ANANTA
                </span>
            </div>
        </div>

        {/* Action Section */}
        <div className="space-y-4 pt-2">
            <div className="flex items-center justify-between gap-4 bg-black/20 p-2 rounded-lg border border-white/10">
                <Button 
                    variant="ghost" 
                    size="icon"
                    className="text-white hover:bg-white/10"
                    onClick={() => setTicketAmount(Math.max(1, ticketAmount - 1))}
                >
                    <Minus className="w-4 h-4" />
                </Button>
                
                <div className="flex flex-col items-center w-full">
                    <span className="text-xs text-slate-500 font-semibold uppercase">Số lượng vé</span>
                    <Input 
                        type="number" 
                        className="border-none bg-transparent text-center text-2xl font-bold text-white focus-visible:ring-0 p-0 h-auto"
                        value={ticketAmount}
                        onChange={(e) => setTicketAmount(Math.max(1, parseInt(e.target.value) || 0))}
                    />
                </div>

                <Button 
                    variant="ghost" 
                    size="icon"
                    className="text-white hover:bg-white/10"
                    onClick={() => setTicketAmount(ticketAmount + 1)}
                >
                    <Plus className="w-4 h-4" />
                </Button>
            </div>

            <Button 
                onClick={onBuyTicket} 
                disabled={!account || isBuying}
                className="w-full h-14 text-lg font-bold bg-gradient-to-r from-cyan-500 via-blue-500 to-indigo-500 hover:from-cyan-600 hover:to-indigo-600 transition-all duration-300 shadow-[0_0_20px_rgba(34,211,238,0.3)] hover:shadow-[0_0_30px_rgba(34,211,238,0.6)]"
            >
                {isBuying ? (
                    <RefreshCw className="mr-2 h-5 w-5 animate-spin" />
                ) : (
                    <Ticket className="mr-2 h-5 w-5" />
                )}
                {isBuying ? "Đang xử lý..." : `MUA ${ticketAmount} VÉ NGAY`}
            </Button>

            {!account && (
                <p className="text-xs text-red-400 text-center animate-pulse">
                    ⚠️ Vui lòng kết nối ví để tham gia
                </p>
            )}
            
            {/* Hiển thị số dư ANANTA của User */}
            {account && (
                <div className="flex justify-between items-center text-xs px-2">
                    <span className="text-slate-400 flex items-center gap-1">
                        <Coins className="w-3 h-3"/> Số dư: <span className="text-white font-bold">{userBalance ? formatToken(userBalance) : "0"}</span> ANANTA
                    </span>
                    <span className="text-slate-400">
                        Tổng: <span className="text-cyan-400 font-bold">{gameData ? formatToken((BigInt(ticketAmount) * BigInt(gameData.price_ticket)).toString()) : 0} ANANTA</span>
                    </span>
                </div>
            )}
        </div>
      </CardContent>
    </Card>
  );
}