
#property copyright "thxssio"
#property version   "1.00"

// Inclusão de bibliotecas utilizadas
#include <Trade/SymbolInfo.mqh>
CSymbolInfo simbolo; // Classe responsãvel pelos dados do ativo

// Momentum
input int                  periodoMomentum     = 10; //Periodo do Momentum
input ENUM_APPLIED_PRICE   aplicadoMomentum    = PRICE_CLOSE; //Momentum aplicado a

// Média móvel no momentum
input int                  periodoMedia   = 3; //Periodo da média móvel
input int                  deslocamento   = 0;  //Deslocamento da média
input ENUM_MA_METHOD       metodoMM       = MODE_SMA; //Média tipo

// Estocástico
input int                  periodoK      = 8; //Periodo K Estocastico
input int                  periodoD      = 3; //Periodo D Estocastico
input int                  suavizacao    = 3; //Suavização
input ENUM_STO_PRICE       aplicadoEst   = STO_CLOSECLOSE; //Metodo Estocastico
input ENUM_MA_METHOD       metodoEst     = MODE_SMA; //Tipo da suavização
input int                  sobreCompra    = 80; //Nível de sobrecompra
input int                  sobreVenda     = 20; //Nível de sobrevenda       

// ATR
input int                  periodoATR     = 20; //Periodo do ATR

input int                  ativarBE       = 1; //Ativar BE (1=sim ; 0=não)
input int                  numeroPerdas   = 3; //Numero de perdas no dia

input ENUM_TRADE_REQUEST_ACTIONS TipoAction = TRADE_ACTION_PENDING; // Tipo de Ordem Enviada
input double   Distancia       = 5;      // Distância da Ordem (ordens pendentes)
input double   SL              = 1.0;      // Stop Loss (vezes o ATR)
input double   TP              = 1.5;      // Take Profit (vezes o ATR)
input double   BE              = 0.5;       // Break Even (% do ATR)
input double   Ganho           = 0.1;       // Ganho Break Even (% do ATR)
input double   Volume          = 1;        // Volume
input int      proxima_operacao = 5;  // Tempo entre operações (em minutos)
input int      excluirOrdem    = 15; //Excluir Ordem Pendente (em minutos)
input string   inicio          = "09:00";  // Horário de Início (entradas)
input string   termino         = "17:50";  // Horário de Término (entradas)
input string   fechamento      = "17:55";  // Horário de Fechamento (posições)

int handleMedia, handleMomentum, handleATR, handleEst; // Manipuladores dos dois indicadores de média móvel

//--- Estruturas de negociação
MqlTradeRequest request;
MqlTradeResult result;
MqlTradeCheckResult check_result;

// Estruturas de tempo para manipulação de horários
MqlDateTime horario_inicio, horario_termino, horario_fechamento, horario_atual;

//Obtenção do histórico
MqlDateTime inicio_struct;

MqlTick ultimoTick;
MqlRates candle[];

int magic = 1234; // Número mágico das ordens

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---   
   // Definição do símbolo utilizado para a classe responsável
   if(!simbolo.Name(_Symbol))
   {
      printf("Ativo Inválido!");
      return INIT_FAILED;
   }
   
   // Criação dos manipuladores com Períodos curto e longo   
   handleMomentum   = iMomentum(_Symbol, _Period, periodoMomentum, aplicadoMomentum);
   handleMedia = iMA(_Symbol, _Period, periodoMedia, deslocamento, metodoMM, handleMomentum);
   handleATR = iATR(_Symbol, _Period, periodoATR);
   handleEst = iStochastic(_Symbol, _Period, periodoK, periodoD, suavizacao, metodoEst, aplicadoEst);
   
   // Verificação do resultado da criação dos manipuladores
   if(handleMedia == INVALID_HANDLE || handleMomentum == INVALID_HANDLE || handleEst == INVALID_HANDLE || handleATR == INVALID_HANDLE)
   {
      Print("Erro na criação dos manipuladores");
      return INIT_FAILED;
   }
//---
   
   // Criação das structs de tempo
   TimeToStruct(StringToTime(inicio), horario_inicio);
   TimeToStruct(StringToTime(termino), horario_termino);
   TimeToStruct(StringToTime(fechamento), horario_fechamento);
   //TimeToStruct(StringToTime(operacao), proxima_operacao);
   
   // Verificação de inconsistências nos parâmetros de entrada
   if(horario_inicio.hour > horario_termino.hour || (horario_inicio.hour == horario_termino.hour && horario_inicio.min > horario_termino.min))
   {
      printf("Parâmetros de Horário inválidos!");
      return INIT_FAILED;
   }
   
   // Verificação de inconsistências nos parâmetros de entrada
   if(horario_termino.hour > horario_fechamento.hour || (horario_termino.hour == horario_fechamento.hour && horario_termino.min > horario_fechamento.min))
   {
      printf("Parâmetros de Horário inválidos!");
      return INIT_FAILED;
   }
   
   // Checar se ordem é pendente ou a mercado e determinar trade action
   if(TipoAction!=TRADE_ACTION_DEAL && TipoAction!= TRADE_ACTION_PENDING)
   {
      printf("Tipo de ordem não permitido");
      return INIT_FAILED;
   }
   
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   // Motivo da desinicialização do EA
   printf("Deinit reason: %d", reason);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---   
    if(!SymbolInfoTick(Symbol(),ultimoTick))
         {
            Alert("Erro ao obter informações de Preços: ", GetLastError());
            return;
         }
   
   // Atualização dos dados do ativo
   if(!simbolo.RefreshRates())
      return;
   
   // EA em horário de entrada em novas operações
   if(HorarioEntrada() && resumoOperacoes() == 0)
   {
      // EA não está posicionado
      if(SemPosicao() && SemOrdem())
      {
         
         ObjectDelete(0, "BE");
         
         // Verificar estratégia e determinar compra ou venda
         int resultado_estrategia = Estrategia();
         
         // Estratégia indicou compra
         if(resultado_estrategia == 1)
            {Compra();}
         // Estratégia indicou venda
         if(resultado_estrategia == -1)
            {Venda();}
      }
      
      // EA está posicionado
      if(!SemPosicao())
      {
         if(ativarBE == 1)
            {BreakEven();}
                    
      }
      
   }
   
   if(!SemOrdem())
     {
      if(timeOrder() == 1)
        {
         Fechar();
        }
     }
   
   // EA está posicionado, fechar posição
   if(HorarioFechamento())
   {
         // EA em horário de fechamento de posições abertas
         if(!SemPosicao() || !SemOrdem())
         {            
            Fechar();
         }
   }
  }
//+------------------------------------------------------------------+
//| Checar se horário atual está dentro do horário de entradas       |
//+------------------------------------------------------------------+
bool HorarioEntrada()
{
   TimeToStruct(TimeCurrent(), horario_atual); // Obtenção do horário atual
   
   // Hora dentro do horário de entradas
   if(horario_atual.hour >= horario_inicio.hour && horario_atual.hour <= horario_termino.hour)
   {
      // Hora atual igual a de início
      if(horario_atual.hour == horario_inicio.hour)
         // Se minuto atual maior ou igual ao de início => está no horário de entradas
         if(horario_atual.min >= horario_inicio.min)
            return true;
         // Do contrário não está no horário de entradas
         else
            return false;
      
      // Hora atual igual a de término
      if(horario_atual.hour == horario_termino.hour)
         // Se minuto atual menor ou igual ao de término => está no horário de entradas
         if(horario_atual.min <= horario_termino.min)
            return true;
         // Do contrário não está no horário de entradas
         else
            return false;
      
      // Hora atual maior que a de início e menor que a de término
      return true;
   }
   
   // Hora fora do horário de entradas
   return false;
}
//+------------------------------------------------------------------+
//| Checar se horário atual está dentro do horário de fechamento     |
//+------------------------------------------------------------------+
bool HorarioFechamento()
{
   TimeToStruct(TimeCurrent(), horario_atual); // Obtenção do horário atual
   
   // Hora dentro do horário de fechamento
   if(horario_atual.hour >= horario_fechamento.hour)
   {
      // Hora atual igual a de fechamento
      if(horario_atual.hour == horario_fechamento.hour)
      {
         // Se minuto atual maior ou igual ao de fechamento => está no horário de fechamento
         if(horario_atual.min >= horario_fechamento.min)
            {return true;}
         // Do contrário não está no horário de fechamento
         else
            {return false;}
       }      
      // Hora atual maior que a de fechamento
      return true;
   }
   
   // Hora fora do horário de fechamento
   else
      {return false;}
}
//+------------------------------------------------------------------+
//| Realizar compra com parâmetros especificados por input           |
//+------------------------------------------------------------------+
void  Compra()
{

   double price, ATR[];
   ArraySetAsSeries(ATR, true);
   CopyBuffer(handleATR, 0, 0, 2, ATR);
   ArraySetAsSeries(candle, true);
   CopyRates(_Symbol, _Period, 0, 3, candle);
     
   if(TipoAction==TRADE_ACTION_DEAL) // Determinação do preço da ordem a mercado
      {price = simbolo.Ask();} 
   else
      {price = candle[1].high + Distancia;}
   double stoploss = simbolo.NormalizePrice(candle[1].low); // Cálculo normalizado do stoploss
   double takeprofit = simbolo.NormalizePrice(price + (candle[1].close - candle[2].low));
  
   // Limpar informações das estruturas "
   ZeroMemory(request);
   ZeroMemory(result);
   ZeroMemory(check_result);
   
   //--- Preenchimento da requisição
   request.action       =TipoAction;
   request.magic        =magic;
   request.symbol       =_Symbol;
   request.volume       =Volume;
   request.price        =price; 
   request.sl           =stoploss;
   request.tp           =takeprofit;
   if(TipoAction==TRADE_ACTION_DEAL)
      {request.type=ORDER_TYPE_BUY;}
   else
      {request.type      =ORDER_TYPE_BUY_STOP;}
   request.type_filling =ORDER_FILLING_RETURN;
   request.type_time    =ORDER_TIME_DAY;
   request.comment      ="Compra CruzamentoMediaEA";
   
   //--- Checagem e envio de ordens
   ResetLastError();
   if(!OrderCheck(request, check_result))
   {
      PrintFormat("Erro em OrderCheck: %d", GetLastError());
      PrintFormat("Código de Retorno: %d", check_result.retcode);
      return;
   }
   
   if(!OrderSend(request, result))
   {
      PrintFormat("Erro em OrderSend: %d", GetLastError());
      PrintFormat("Código de Retorno: %d", result.retcode);
      return;
   }
   
   ObjectCreate(0, "BE", OBJ_HLINE, 0, 0, price + BE);
}
//+------------------------------------------------------------------+
//| Realizar venda com parâmetros especificados por input            |
//+------------------------------------------------------------------+
void Venda()
{
   double price, ATR[];
   ArraySetAsSeries(ATR, true);
   CopyBuffer(handleATR, 0, 0, 2, ATR);
   ArraySetAsSeries(candle, true);
   CopyRates(_Symbol, _Period, 0, 3, candle);
   
   if(TipoAction==TRADE_ACTION_DEAL) // Determinação do preço da ordem a mercado
      price = simbolo.Bid(); 
   else
      price = candle[1].low - Distancia;
   double stoploss = simbolo.NormalizePrice(candle[1].high); // Cálculo normalizado do stoploss
   double takeprofit = simbolo.NormalizePrice(price - (candle[2].high - candle[1].close));
   
   // Limpar informações das estruturas
   ZeroMemory(request);
   ZeroMemory(result);
   ZeroMemory(check_result);
   
   //--- Preenchimento da requisição
   request.action       =TipoAction;
   request.magic        =magic;
   request.symbol       =_Symbol;
   request.volume       =Volume;
   request.price        =price; 
   request.sl           =stoploss;
   request.tp           =takeprofit;
   request.type_filling =ORDER_FILLING_FOK; 
   request.type_time    =ORDER_TIME_SPECIFIED;
   if(TipoAction==TRADE_ACTION_DEAL)
     {request.type=ORDER_TYPE_SELL;}
   else
     {request.type=ORDER_TYPE_SELL_STOP;}
   request.type_filling  = ORDER_FILLING_RETURN;
   request.type_time     = ORDER_TIME_DAY;
   request.comment       = "Venda CruzamentoMediaEA";
   
   //--- Checagem e envio de ordens
   ResetLastError();
   if(!OrderCheck(request, check_result))
   {
      PrintFormat("Erro em OrderCheck: %d", GetLastError());
      PrintFormat("Código de Retorno: %d", check_result.retcode);
      return;
   }
   
   if(!OrderSend(request, result))
   {
      PrintFormat("Erro em OrderSend: %d", GetLastError());
      PrintFormat("Código de Retorno: %d", result.retcode);
      return;
   }
   
   ObjectCreate(0, "BE", OBJ_HLINE, 0, 0, price - BE);
}
//+------------------------------------------------------------------+
//| Fechar posição aberta                                            |
//+------------------------------------------------------------------+
void Fechar()
{  
   if(OrdersTotal() != 0)
   {
      for(int i=OrdersTotal()-1; i>=0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(OrderGetString(ORDER_SYMBOL)==_Symbol)
         {
            ZeroMemory(request);
            ZeroMemory(result);
            ZeroMemory(check_result);
            request.action       =TRADE_ACTION_REMOVE;
            request.order        =ticket;
            
            //--- Checagem e envio de ordens
            ResetLastError();
            if(!OrderCheck(request, check_result))
            {
               PrintFormat("Erro em OrderCheck: %d", GetLastError());
               PrintFormat("Código de Retorno: %d", check_result.retcode);
               return;
            }
            
            if(!OrderSend(request, result))
            {
               PrintFormat("Erro em OrderSend: %d", GetLastError());
               PrintFormat("Código de Retorno: %d", result.retcode);
            }
         }
      }
   }
   
   // Verificação de posição aberta
   if(!PositionSelect(_Symbol))
      return;
      
   // Limpar informações das estruturas
   ZeroMemory(request);
   ZeroMemory(result);
   ZeroMemory(check_result);
   
   //--- Preenchimento da requisição
   request.action       =TRADE_ACTION_DEAL;
   request.magic        =magic;
   request.symbol       =_Symbol;
   request.volume       =Volume;
   request.type_filling =ORDER_FILLING_RETURN; 
   request.comment      ="Fechamento CruzamentoMediaEA";
      
   long tipo = PositionGetInteger(POSITION_TYPE); // Tipo da posição aberta
   
   // Vender em caso de posição comprada
   if(tipo == POSITION_TYPE_BUY)
   {
      request.price        =simbolo.Bid(); 
      request.type         =ORDER_TYPE_SELL;
   }
   // Comprar em caso de posição vendida
   else
   {
      request.price        =simbolo.Ask(); 
      request.type         =ORDER_TYPE_BUY;
   }
   
   //--- Checagem e envio de ordens
   ResetLastError();
   if(!OrderCheck(request, check_result))
   {
      PrintFormat("Erro em OrderCheck: %d", GetLastError());
      PrintFormat("Código de Retorno: %d", check_result.retcode);
      return;
   }
   
   if(!OrderSend(request, result))
   {
      PrintFormat("Erro em OrderSend: %d", GetLastError());
      PrintFormat("Código de Retorno: %d", result.retcode);
   }
}
//+------------------------------------------------------------------+
//| Verificar se há posição aberta                                   |
//+------------------------------------------------------------------+
bool SemPosicao()
{  
   bool resultado = !PositionSelect(_Symbol);
   return resultado;
}
//+------------------------------------------------------------------+
//| Verificar se há ordem aberta                                     |
//+------------------------------------------------------------------+
bool SemOrdem()
{  
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      OrderGetTicket(i);
      if(OrderGetString(ORDER_SYMBOL)==_Symbol)
         return false;
   }
   return true;
}
//+------------------------------------------------------------------+
//| Estratégia de cruzamento de médias                               |
//+------------------------------------------------------------------+
int Estrategia()
{
   double media[], mom[], Est[], sinalEst[];
   
   ArraySetAsSeries(Est, true);
   ArraySetAsSeries(mom, true);
   ArraySetAsSeries(media, true);
   ArraySetAsSeries(candle, true);
   ArraySetAsSeries(sinalEst, true);
   CopyBuffer(handleEst, 0, 0, 3, Est);
   CopyBuffer(handleEst, 1, 0, 3, sinalEst);
   CopyBuffer(handleMedia, 0, 0, 3, media);
   CopyBuffer(handleMomentum, 0, 0, 3, mom);  
   CopyRates(_Symbol, _Period, 0, 3, candle);
      
   // Compra
   if( 
      candle[2].close <= candle[1].open && candle[2].close < candle[1].close && //candles
      Est[2] < Est[1] && sinalEst[2] < sinalEst[1] && Est[1] > sinalEst[1] &&  Est[1] < sobreCompra &&//Estocástico
      mom[2] < mom[1] && media[2] < media[1] && mom[1] > media[1] //Momentum
     )
      {return 1;}
   
   // Venda
   if( 
      candle[2].close >= candle[1].open && candle[2].close > candle[1].close && //candles
      Est[2] > Est[1] && sinalEst[2] > sinalEst[1] && Est[1] < sinalEst[1] && Est[1] > sobreVenda && //Estocástico
      mom[2] > mom[1] && media[2] > media[1] && mom[1] < media[1] //Momentum      
     )
      {return -1;}
      
   return 0;
}
void BreakEven()
{
   if(!PositionSelect(_Symbol))
      return;
      
   double preco_abertura = PositionGetDouble(POSITION_PRICE_OPEN);
   double delta = simbolo.Last() - preco_abertura;
   double sl = PositionGetDouble(POSITION_SL);
   double ATR[];
   
   ArraySetAsSeries(ATR, true);
   CopyBuffer(handleATR, 0, 0, 2, ATR);
   //--- Inverter delta para posição vendida
   if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL)
      delta *= -1;
   
   if(sl == preco_abertura + Ganho * ATR[1])
      return;
   
   if(delta >= BE * ATR[1])
   {
      //--- Estruturas de negociação
      ZeroMemory(request);
      ZeroMemory(result);
      ZeroMemory(check_result);
      //---
      
      //--- Preenchimento da requisição
      request.action = TRADE_ACTION_SLTP;                               // Tipo de operação de negociação 
      request.magic = magic;                                            // Expert Advisor -conselheiro- ID (número mágico) 
      request.symbol = _Symbol;                                         // Símbolo de negociação 
      request.sl = preco_abertura + Ganho * ATR[1];                              // Nível Stop Loss da ordem 
      request.tp = PositionGetDouble(POSITION_TP);                      // Nível Take Profit da ordem 
      request.position = PositionGetInteger(POSITION_TICKET);           // Bilhete da posição 
      //---
      //--- Checagem e envio de ordens
      ResetLastError();
      if(!OrderCheck(request, check_result))
      {
         PrintFormat("Erro em OrderCheck: %d", GetLastError());
         PrintFormat("Código de Retorno: %d", check_result.retcode);
         return;
      }
      
      if(!OrderSend(request, result))
      {
         PrintFormat("Erro em OrderSend: %d", GetLastError());
         PrintFormat("Código de Retorno: %d", result.retcode);
         return;
      }
      
      ObjectDelete(0, "BE");
      //---
   }
}
//+------------------------------------------------------------------+

int resumoOperacoes()
{
   //Declaração de variáveis
   datetime comeco, fim;
   double lucro = 0, perda = 0;
   int trades = 0, stopLoss = 0;
   
   double resultadoOperacao;
   ulong ticketOperacao;
   long saidaOperacao;

   fim = TimeCurrent(inicio_struct);
   inicio_struct.hour = 0;
   inicio_struct.min  = 0;
   inicio_struct.sec  = 0;
   comeco = StructToTime(inicio_struct);
   
   HistorySelect(comeco, fim);
   
   //Cálculos
   if(HistoryDealsTotal() != 0)
   {
   for(int i=0; i< HistoryDealsTotal(); i++)
   {
      ticketOperacao = HistoryDealGetTicket(i);
      if(ticketOperacao>0)
      {
         if(HistoryDealGetString(ticketOperacao, DEAL_SYMBOL) == _Symbol)
         {
            trades++;
            resultadoOperacao = HistoryDealGetDouble(ticketOperacao, DEAL_PROFIT); 
            if(resultadoOperacao < 0)
            {
               //TimeToStruct(HistoryDealGetInteger(ticketOperacao, DEAL_TIME), saidaOperacao);
               saidaOperacao = HistoryDealGetInteger(ticketOperacao, DEAL_TIME);
               if((saidaOperacao + proxima_operacao*60) >= TimeCurrent())               
               {return 1;}
               perda+= -resultadoOperacao;
               stopLoss++;
               if(stopLoss == numeroPerdas)
               {return 1;}
            }
            else
            {
               lucro += resultadoOperacao;
               saidaOperacao = HistoryDealGetInteger(ticketOperacao, DEAL_TIME);
               if((saidaOperacao + proxima_operacao*60) >= TimeCurrent())               
               {return 1;}
               
            }
         }  
         
      }
   }
   double fator_lucro;
   if(perda > 0)
   {
      fator_lucro = lucro / perda;
   }
   else
   {
      fator_lucro = -1;
   }
   double resultado_liquido = lucro - perda;
   
   //Exibição
   Comment("Trades: ", trades, 
           " Lucro: ", DoubleToString(lucro, 2), 
           " Perdas: ", DoubleToString(perda, 2),
           " Resultados: ", DoubleToString(resultado_liquido, 2),
           " FL: ", DoubleToString(fator_lucro, 2),
           " SL: ", DoubleToString(stopLoss, 2));
           
   
   }
   return 0;
   
}

int timeOrder()
{
   datetime comeco, fim;
   ulong ticketOrder;
   
   fim = TimeCurrent(inicio_struct);
   inicio_struct.hour = 0;
   inicio_struct.min  = 0;
   inicio_struct.sec  = 0;
   comeco = StructToTime(inicio_struct);
   
   HistorySelect(comeco, fim);
   
   if(HistoryOrdersTotal() != 0)
     {
      for(int i=0; i<HistoryOrdersTotal() ;i++)
        {
         ticketOrder = HistoryOrderGetTicket(i);
         if(ticketOrder > 0)
           {
            if(HistoryOrderGetString(ticketOrder, ORDER_SYMBOL) == _Symbol)
              {
               long timeSetup = HistoryOrderGetInteger(ticketOrder, ORDER_TIME_SETUP);
               if((timeSetup + excluirOrdem * 60) > TimeCurrent())
                 {return 0;}
              }
           }
        }   
     }
   return 1;
}
//+------------------------------------------------------------------+