//+------------------------------------------------------------------+
//|                                   DynamicEquidistantChannel.mq5  |
//|            Динамика и автосдвиг равноудаленных каналов           |
//+------------------------------------------------------------------+
//| ИСПОЛЬЗОВАНИЕ (v2.00)                                            |
//|  1. Нарисуйте стандартный равноудаленный канал точками в порядке |
//|     А -> В -> С:                                                 |
//|       А (точка 0) - нижняя точка задающей границы на стартовом   |
//|                      баре (у нисходящего - верхняя);             |
//|       В (точка 1) - верхняя точка задающей границы (у            |
//|                      нисходящего - нижняя);                      |
//|       С (точка 2) - точка на равноудаленной границе.             |
//|     Восходящий канал по ценам якорей: В > С > А.                 |
//|     Нисходящий: зеркально (В < С < А).                           |
//|  2. БЕЗ клика канал - обычный стандартный объект: индикатор его  |
//|     не трогает, пока в его описании нет кода настроек "DEQ ...". |
//|  3. КЛИКНИТЕ канал - откроется окно свойств динамики:            |
//|     активность, события и пуши, отображение следов, поведение    |
//|     при реактивации/удалении. "Применить" - настройки пишутся в  |
//|     описание объекта (живут в самом канале).                     |
//|  4. АКТИВАЦИЯ: если якорь С левее текущего бара - история        |
//|     восстанавливается побарно от вертикали С (ретро-след),       |
//|     с текущего бара работает потиковая обработка. События и      |
//|     пуши - только с момента активации.                           |
//|  5. Активный канал: ручное перетаскивание якорей останавливает   |
//|     динамику (пауза + уведомление). Возобновление - клик по      |
//|     каналу -> "Применить".                                       |
//|  6. Смерть канала: уведомление, динамика и рисовка останавлива-  |
//|     ются. Дальше оператор: удаляет канал (по настройке "удаление |
//|     канала: стереть следы" следы стираются или остаются снимком) |
//|     или двигает канал и реактивирует ("реактивация: стереть и    |
//|     начать заново" или продолжение серии).                       |
//|  Цвет/толщину/лучи канала настраивайте штатными средствами:     |
//|  след В рисуется цветом канала, след Д - тем же цветом бледнее  |
//|  и ромбами вместо точек.                                         |
//|  Динамик МА (галка в окне канала): SMA по Close от бара А до    |
//|  текущего бара В, снимок на каждом закрытии. Касание МА - пуш;  |
//|  экстремум бара (фитиль) за МА на >=1 пп против С - точка С на  |
//|  этот экстремум: к А - всегда, к В - после нового экстремума В. |
//|  Цвет - как у канала.                                            |
//|  Статус всех каналов - в левом верхнем углу графика.             |
//+------------------------------------------------------------------+
#property copyright   "Максим"
#property version     "3.05"
#property description "Сопровождение всех равноудаленных каналов графика: динамика, ретро-след, уведомления."
#property description "Клик по каналу - окно свойств динамики. Настройки хранятся в описании объекта."
#property indicator_chart_window
#property indicator_plots 0

//--- Рабочий режим
input group "Рабочий режим"
input ENUM_TIMEFRAMES InpWorkTF = PERIOD_CURRENT; // Рабочий ТФ (бары динамики)

//--- Уведомления
input group "Уведомления"
input bool InpAlertPopup = true;   // Alert в терминале
input bool InpAlertPush  = false;  // Push на телефон

//--- Следы динамики: цвет берется из цвета основного канала
//--- (В - цвет канала, Д - тот же цвет бледнее + другой значок)

//--- Подписи точек
input group "Подписи точек"
input color InpLabelColor    = clrSilver; // Цвет подписей А/В/С
input int   InpLabelFontSize = 10;        // Размер шрифта подписей

//+------------------------------------------------------------------+
//| Состояние канала                                                 |
//+------------------------------------------------------------------+
enum EChanState
  {
   CS_OFF=0,     // динамика выключена (a=0)
   CS_ACTIVE=1,  // работает
   CS_PAUSED=2,  // пауза: ручная правка активного канала
   CS_DEAD=3     // канал умер
  };

struct SChannel
  {
   //--- идентификация и настройки (хранятся в описании объекта)
   string     name;
   bool       setA;        // активность динамики
   bool       setDead;     // пуш: канал умер
   int        setPushC;    // пуши: перерисовка C (0=выкл)
   int        setPushB;    // пуши: перерисовка B (0=выкл)
   int        setPushT;    // пуши: касание линии C (0=выкл)
   int        setPushM;    // пуши: касание Динамик МА (0=выкл)
   bool       setMA;       // Динамик МА: след, касание, сдвиг C по пробою
   int        setTol;      // допуск касания, пунктов
   bool       setPts;      // следы: точки
   bool       setLines;    // следы: линии
   bool       setLabels;   // подписи А/В/С
   bool       setReactNew; // реактивация: стереть и начать заново
   bool       setDelTrace; // удаление канала: стереть следы
   //--- состояние
   EChanState state;
   datetime   tA,tB,tC;
   double     pA,pB,pC;
   double     pB_at_C;    // цена В на момент последнего переноса С (ход к В - только после нового экстремума В)
   bool       up;
   datetime   lastBar;
   datetime   lastTraceBar;
   datetime   lastBT;
   double     lastBP;
   datetime   lastDT;
   double     lastDP;
   datetime   lastMAT;     // последний снимок Динамик МА
   double     lastMAP;
   double     dmaSum;      // бегущая сумма Close окна А..тек.бар (ретро)
   long       dmaCnt;
   bool       fC,fB,fTouch,fTouchM;
   int        cntC,cntB,cntT,cntM;
   bool       labelsDirty;
   int        nLB,nLC;
   int        nLM;
  };

SChannel       g_ch[];
int            g_nCh=0;
long           g_runid=0;
ENUM_TIMEFRAMES g_tf=PERIOD_CURRENT;
string         g_dlgChanName="";
bool           g_dlgOpen=false;
string         g_lastStatus="";

//+------------------------------------------------------------------+
//| Уведомление оператору                                            |
//+------------------------------------------------------------------+
void Notify(const int i,const string msg)
  {
   if(!InpAlertPopup && !InpAlertPush)
      return;
   string text=StringFormat("[Канал %s] %s",g_ch[i].name,msg);
   if(InpAlertPopup)
      Alert(text);
   if(InpAlertPush)
     {
      if(!SendNotification(text))
         Print("SendNotification failed, code=",GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| Позиция времени в БАРОВОМ пространстве графика                   |
//| Терминал рисует линии объектов линейно по барам: выходные и      |
//| закрытия рынка на шкале сжаты. Расчет тоже ведем в барах.        |
//+------------------------------------------------------------------+
double BarPos(const datetime t)
  {
   int i=iBarShift(_Symbol,_Period,t,false);
   if(i<0)
      return 0.0;
   datetime tb=iTime(_Symbol,_Period,i);
   double frac=0.0;
   long span=PeriodSeconds(_Period);
   if(span>0 && t>tb)
      frac=(double)(t-tb)/(double)span;
   return (double)i-frac;
  }

//+------------------------------------------------------------------+
//| Значение границы АВ в момент t (как на экране терминала)         |
//+------------------------------------------------------------------+
double LineAB(const int i,const datetime t)
  {
   double d=BarPos(g_ch[i].tB)-BarPos(g_ch[i].tA);
   if(d==0.0)
      return g_ch[i].pB;
   return g_ch[i].pA+(g_ch[i].pB-g_ch[i].pA)*(BarPos(t)-BarPos(g_ch[i].tA))/d;
  }

//+------------------------------------------------------------------+
//| Значение границы С (паралель АВ через С) в момент t              |
//+------------------------------------------------------------------+
double LineC(const int i,const datetime t)
  {
   double d=BarPos(g_ch[i].tB)-BarPos(g_ch[i].tA);
   if(d==0.0)
      return g_ch[i].pC;
   return g_ch[i].pC+(g_ch[i].pB-g_ch[i].pA)*(BarPos(t)-BarPos(g_ch[i].tC))/d;
  }

//+------------------------------------------------------------------+
//| Динамик МА: SMA по Close, окно от бара А до бара shift вкл.      |
//| Возвращает 0.0, если закрытых баров от А еще нет                 |
//+------------------------------------------------------------------+
double DMAValue(const int i,const int shift)
  {
   if(shift<1)
      return 0.0;
   int iA=iBarShift(_Symbol,g_tf,g_ch[i].tA,false);
   if(iA<shift)
      return 0.0;
   double s=0.0;
   long   n=0;
   for(int b=iA;b>=shift;b--)
     {
      double c=iClose(_Symbol,g_tf,b);
      if(c>0.0)
        {
         s+=c;
         n++;
        }
     }
   return (n>0)? s/n : 0.0;
  }

//+------------------------------------------------------------------+
//| Перенос якорей объекта канала                                    |
//+------------------------------------------------------------------+
void MoveB(const int i,const datetime t,const double p)
  {
   g_ch[i].tB=t;
   g_ch[i].pB=p;
   ObjectMove(0,g_ch[i].name,1,t,p);
   g_ch[i].labelsDirty=true;
  }

void MoveC(const int i,const datetime t,const double p)
  {
   g_ch[i].tC=t;
   g_ch[i].pC=p;
   ObjectMove(0,g_ch[i].name,2,t,p);
   g_ch[i].labelsDirty=true;
  }

//+------------------------------------------------------------------+
//| Чтение якорей A(0), B(1), C(2) из объекта                        |
//+------------------------------------------------------------------+
bool ReadAnchors(const int i)
  {
   if(ObjectFind(0,g_ch[i].name)<0)
      return false;
   g_ch[i].tA=(datetime)ObjectGetInteger(0,g_ch[i].name,OBJPROP_TIME,0);
   g_ch[i].tB=(datetime)ObjectGetInteger(0,g_ch[i].name,OBJPROP_TIME,1);
   g_ch[i].tC=(datetime)ObjectGetInteger(0,g_ch[i].name,OBJPROP_TIME,2);
   g_ch[i].pA=ObjectGetDouble(0,g_ch[i].name,OBJPROP_PRICE,0);
   g_ch[i].pB=ObjectGetDouble(0,g_ch[i].name,OBJPROP_PRICE,1);
   g_ch[i].pC=ObjectGetDouble(0,g_ch[i].name,OBJPROP_PRICE,2);
   return (g_ch[i].tA>0 && g_ch[i].tB>0 && g_ch[i].tC>0 && g_ch[i].tB!=g_ch[i].tA);
  }

//+------------------------------------------------------------------+
//| Условие "правильности" канала, определяет направление            |
//+------------------------------------------------------------------+
bool GeometryOK(const int i)
  {
   if(g_ch[i].pB>g_ch[i].pA)
     {
      g_ch[i].up=true;
      return (g_ch[i].pB>=g_ch[i].pC && g_ch[i].pC>=g_ch[i].pA);   // равность допустима, за 1 пп - смерть
     }
   if(g_ch[i].pB<g_ch[i].pA)
     {
      g_ch[i].up=false;
      return (g_ch[i].pB<=g_ch[i].pC && g_ch[i].pC<=g_ch[i].pA);   // равность допустима, за 1 пп - смерть
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Подписи точек А/В/С                                              |
//+------------------------------------------------------------------+
string LblName(const string chan,const string id)
  {
   return "DEQL_"+chan+"_"+id;
  }

void SetLabel(const string chan,const string id,const string txt,const datetime t,const double p,const ENUM_ANCHOR_POINT anchor)
  {
   string nm=LblName(chan,id);
   if(ObjectFind(0,nm)<0)
     {
      ObjectCreate(0,nm,OBJ_TEXT,0,t,p);
      ObjectSetInteger(0,nm,OBJPROP_COLOR,InpLabelColor);
      ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,InpLabelFontSize);
      ObjectSetString(0,nm,OBJPROP_FONT,"Arial");
      ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,nm,OBJPROP_HIDDEN,true);
     }
   ObjectSetString(0,nm,OBJPROP_TEXT,txt);
   ObjectSetInteger(0,nm,OBJPROP_ANCHOR,anchor);
   ObjectMove(0,nm,0,t,p);
  }

void UpdateLabels(const int i)
  {
   if(!g_ch[i].labelsDirty)
      return;
   g_ch[i].labelsDirty=false;
   if(!g_ch[i].setLabels)
      return;
   if(ObjectFind(0,g_ch[i].name)<0)
      return;
   SetLabel(g_ch[i].name,"A","А",g_ch[i].tA,g_ch[i].pA,ANCHOR_UPPER);
   SetLabel(g_ch[i].name,"B","В",g_ch[i].tB,g_ch[i].pB,ANCHOR_LOWER);
   SetLabel(g_ch[i].name,"C","С",g_ch[i].tC,g_ch[i].pC,ANCHOR_UPPER);
  }

void DeleteLabels(const string chan)
  {
   ObjectDelete(0,LblName(chan,"A"));
   ObjectDelete(0,LblName(chan,"B"));
   ObjectDelete(0,LblName(chan,"C"));
  }

//+------------------------------------------------------------------+
//| Счетчики пушей: глобальные переменные терминала                  |
//+------------------------------------------------------------------+
string GVCnt(const string chan,const string id)
  {
   string key=chan;
   if(StringLen(key)>24)
      key=StringSubstr(key,0,24);
   return "DEQ_CNT_"+id+"_"+key;
  }

//+------------------------------------------------------------------+
//| Число в конце имени объекта (после последнего '_')               |
//+------------------------------------------------------------------+
int NameIdx(const string nm)
  {
   int k=StringLen(nm)-1;
   while(k>=0)
     {
      ushort c=StringGetCharacter(nm,k);
      if(c<'0' || c>'9')
         break;
      k--;
     }
   if(k==StringLen(nm)-1)
      return -1;
   return (int)StringToInteger(StringSubstr(nm,k+1));
  }

//+------------------------------------------------------------------+
//| Удалить следы канала (все запуски) + следы старых версий         |
//+------------------------------------------------------------------+
void ClearTraces(const string chan)
  {
   string pB="DEQT_PB_"+chan+"_";
   string pD="DEQT_PD_"+chan+"_";
   string lB="DEQT_LB_"+chan+"_";
   string lD="DEQT_LD_"+chan+"_";
   string pM="DEQT_PM_"+chan+"_";
   string lM="DEQT_LM_"+chan+"_";
   for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--)
     {
      string nm=ObjectName(0,i,-1,-1);
      bool del=false;
      if(StringFind(nm,pB)==0 || StringFind(nm,pD)==0 ||
         StringFind(nm,lB)==0 || StringFind(nm,lD)==0 ||
         StringFind(nm,pM)==0 || StringFind(nm,lM)==0)
         del=true;
      else if(StringFind(nm,"DEQ_PB_")==0 || StringFind(nm,"DEQ_PC_")==0 ||
              StringFind(nm,"DEQ_LB_")==0 || StringFind(nm,"DEQ_LC_")==0)
         del=true;                                   // следы старых версий
      if(del)
         ObjectDelete(0,nm);
     }
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Пересобрать следы канала с графика (смена ТФ / перезапуск)       |
//| Возвращает число существующих точек следов                       |
//+------------------------------------------------------------------+
int RebuildTrace(const int i)
  {
   g_ch[i].lastBT=0;
   g_ch[i].lastBP=0.0;
   g_ch[i].lastDT=0;
   g_ch[i].lastDP=0.0;
   g_ch[i].lastMAT=0;
   g_ch[i].lastMAP=0.0;
   g_ch[i].nLB=0;
   g_ch[i].nLC=0;
   g_ch[i].nLM=0;
   string pB="DEQT_PB_"+g_ch[i].name+"_";
   string pD="DEQT_PD_"+g_ch[i].name+"_";
   string lB="DEQT_LB_"+g_ch[i].name+"_";
   string lD="DEQT_LD_"+g_ch[i].name+"_";
   string pM="DEQT_PM_"+g_ch[i].name+"_";
   string lM="DEQT_LM_"+g_ch[i].name+"_";
   int cnt=0;
   int total=ObjectsTotal(0,-1,-1);
   for(int k=0;k<total;k++)
     {
      string nm=ObjectName(0,k,-1,-1);
      if(StringFind(nm,pB)==0)
        {
         datetime t=(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,0);
         double   p=ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
         cnt++;
         if(t>g_ch[i].lastBT || (t==g_ch[i].lastBT && p!=0.0 && g_ch[i].lastBT==0))
           {
            if(g_ch[i].lastBT==0 || t>=g_ch[i].lastBT)
              {
               g_ch[i].lastBT=t;
               g_ch[i].lastBP=p;
              }
           }
        }
      else if(StringFind(nm,pD)==0)
        {
         datetime t=(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,0);
         double   p=ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
         cnt++;
         if(g_ch[i].lastDT==0 || t>=g_ch[i].lastDT)
           {
            g_ch[i].lastDT=t;
            g_ch[i].lastDP=p;
           }
        }
      else if(StringFind(nm,lB)==0)
        {
         int idx=NameIdx(nm);
         if(idx>=g_ch[i].nLB)
            g_ch[i].nLB=idx+1;
        }
      else if(StringFind(nm,lD)==0)
        {
         int idx=NameIdx(nm);
         if(idx>=g_ch[i].nLC)
            g_ch[i].nLC=idx+1;
        }
      else if(StringFind(nm,pM)==0)
        {
         datetime t=(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,0);
         double   p=ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
         cnt++;
         if(g_ch[i].lastMAT==0 || t>=g_ch[i].lastMAT)
           {
            g_ch[i].lastMAT=t;
            g_ch[i].lastMAP=p;
           }
        }
      else if(StringFind(nm,lM)==0)
        {
         int idx=NameIdx(nm);
         if(idx>=g_ch[i].nLM)
            g_ch[i].nLM=idx+1;
        }
     }
   return cnt;
  }

//+------------------------------------------------------------------+
//| Цвета следов из основного канала: В - цвет канала, Д - бледнее   |
//+------------------------------------------------------------------+
color TraceColorB(const int i)
  {
   long c=ObjectGetInteger(0,g_ch[i].name,OBJPROP_COLOR);
   if(c==0)
      c=clrDodgerBlue;
   return (color)c;
  }

color TraceColorD(const int i)
  {
   long base=ObjectGetInteger(0,g_ch[i].name,OBJPROP_COLOR);
   if(base==0)
      base=clrDodgerBlue;
   long bgc=ChartGetInteger(0,CHART_COLOR_BACKGROUND);
   int r =(int)(base&0xFF), g =(int)((base>>8)&0xFF),  b =(int)((base>>16)&0xFF);
   int rb=(int)(bgc&0xFF),  gb=(int)((bgc>>8)&0xFF),  bb=(int)((bgc>>16)&0xFF);
   r=(int)MathRound(r*0.55+rb*0.45);
   g=(int)MathRound(g*0.55+gb*0.45);
   b=(int)MathRound(b*0.55+bb*0.45);
   return (color)((b<<16)|(g<<8)|r);
  }

//+------------------------------------------------------------------+
//| Добавить точку следа (B или D) + линия к предыдущей              |
//+------------------------------------------------------------------+
void AddTrace(const int i,const bool isB,const datetime t,const double p)
  {
   bool     have=false;
   datetime prevT=0;
   double   prevP=0.0;
   if(isB)
     {
      if(g_ch[i].lastBT>0)
        {
         have=true;
         prevT=g_ch[i].lastBT;
         prevP=g_ch[i].lastBP;
        }
     }
   else
     {
      if(g_ch[i].lastDT>0)
        {
         have=true;
         prevT=g_ch[i].lastDT;
         prevP=g_ch[i].lastDP;
        }
     }

   if(g_ch[i].setPts)
     {
      string nm=StringFormat("DEQT_P%s_%s_%I64d",isB?"B":"D",g_ch[i].name,(long)t);
      if(ObjectFind(0,nm)<0)
        {
         ObjectCreate(0,nm,OBJ_ARROW,0,t,p);
         ObjectSetInteger(0,nm,OBJPROP_ARROWCODE,isB?159:119);   // В - точка, Д - ромб
         ObjectSetInteger(0,nm,OBJPROP_COLOR,isB?TraceColorB(i):TraceColorD(i));
         ObjectSetInteger(0,nm,OBJPROP_WIDTH,1);
         ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0,nm,OBJPROP_HIDDEN,true);
         ObjectSetInteger(0,nm,OBJPROP_BACK,false);
        }
     }

   if(g_ch[i].setLines && have)
     {
      string nm="";
      if(isB)
        {
         nm=StringFormat("DEQT_LB_%s_%d",g_ch[i].name,g_ch[i].nLB);
         g_ch[i].nLB++;
        }
      else
        {
         nm=StringFormat("DEQT_LD_%s_%d",g_ch[i].name,g_ch[i].nLC);
         g_ch[i].nLC++;
        }
      ObjectCreate(0,nm,OBJ_TREND,0,prevT,prevP,t,p);
      ObjectSetInteger(0,nm,OBJPROP_COLOR,isB?TraceColorB(i):TraceColorD(i));
      ObjectSetInteger(0,nm,OBJPROP_STYLE,STYLE_DOT);
      ObjectSetInteger(0,nm,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,nm,OBJPROP_RAY_RIGHT,false);
      ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,nm,OBJPROP_HIDDEN,true);
     }

   if(isB)
     {
      g_ch[i].lastBT=t;
      g_ch[i].lastBP=p;
     }
   else
     {
      g_ch[i].lastDT=t;
      g_ch[i].lastDP=p;
     }
  }

//+------------------------------------------------------------------+
//| Снимок Динамик МА на закрытом баре (точка + сплошная линия)      |
//+------------------------------------------------------------------+
void AddMATrace(const int i,const datetime t,const double p)
  {
   if(p<=0.0)
      return;
   if(g_ch[i].setPts)
     {
      string nm=StringFormat("DEQT_PM_%s_%I64d",g_ch[i].name,(long)t);
      if(ObjectFind(0,nm)<0)
        {
         ObjectCreate(0,nm,OBJ_ARROW,0,t,p);
         ObjectSetInteger(0,nm,OBJPROP_ARROWCODE,158);          // малая точка
         ObjectSetInteger(0,nm,OBJPROP_COLOR,TraceColorB(i));   // цвет канала
         ObjectSetInteger(0,nm,OBJPROP_WIDTH,1);
         ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0,nm,OBJPROP_HIDDEN,true);
         ObjectSetInteger(0,nm,OBJPROP_BACK,false);
        }
     }
   if(g_ch[i].setLines && g_ch[i].lastMAT>0)
     {
      string nm=StringFormat("DEQT_LM_%s_%d",g_ch[i].name,g_ch[i].nLM);
      g_ch[i].nLM++;
      ObjectCreate(0,nm,OBJ_TREND,0,g_ch[i].lastMAT,g_ch[i].lastMAP,t,p);
      ObjectSetInteger(0,nm,OBJPROP_COLOR,TraceColorB(i));
      ObjectSetInteger(0,nm,OBJPROP_STYLE,STYLE_SOLID);         // сплошная - отличается от следов
      ObjectSetInteger(0,nm,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,nm,OBJPROP_RAY_RIGHT,false);
      ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,nm,OBJPROP_HIDDEN,true);
     }
   g_ch[i].lastMAT=t;
   g_ch[i].lastMAP=p;
  }

//+------------------------------------------------------------------+
//| Стереть только след Динамик МА канала (галку выключили)          |
//+------------------------------------------------------------------+
void ClearMATrace(const int i)
  {
   string pM="DEQT_PM_"+g_ch[i].name+"_";
   string lM="DEQT_LM_"+g_ch[i].name+"_";
   for(int k=ObjectsTotal(0,-1,-1)-1;k>=0;k--)
     {
      string nm=ObjectName(0,k,-1,-1);
      if(StringFind(nm,pM)==0 || StringFind(nm,lM)==0)
         ObjectDelete(0,nm);
     }
   g_ch[i].lastMAT=0;
   g_ch[i].lastMAP=0.0;
   g_ch[i].nLM=0;
   g_ch[i].dmaSum=0.0;
   g_ch[i].dmaCnt=0;
  }

//+------------------------------------------------------------------+
//| Настройки: код в описании объекта                                |
//| Формат: DEQ a=1 pd=1 pc=1 pb=1 pt=1 pm=1 ma=0 tp=10 kp=1 kl=1 lb=1 rn=0 dd=0 |
//+------------------------------------------------------------------+
void ParseDesc(SChannel &c)
  {
   //--- дефолты
   c.setA=false;
   c.setDead=true;
   c.setPushC=1;
   c.setPushB=1;
   c.setPushT=1;
   c.setPushM=1;
   c.setMA=false;
   c.setTol=10;
   c.setPts=true;
   c.setLines=true;
   c.setLabels=true;
   c.setReactNew=false;
   c.setDelTrace=false;
   //--- читать описание объекта
   string desc="";
   if(ObjectFind(0,c.name)>=0)
      desc=ObjectGetString(0,c.name,OBJPROP_TEXT);
   if(StringFind(desc,"DEQ")!=0)
      return;                                        // канал не сопровождаем (настройки по умолчанию, динамика выкл)
   string parts[];
   int n=StringSplit(desc,' ',parts);
   for(int k=1;k<n;k++)
     {
      string s=parts[k];
      int p=StringFind(s,"=");
      if(p<=0)
         continue;
      string key=StringSubstr(s,0,p);
      int v=(int)StringToInteger(StringSubstr(s,p+1));
      if(key=="a")        c.setA=(v!=0);
      else if(key=="pd")  c.setDead=(v!=0);
      else if(key=="pc")  c.setPushC=v;
      else if(key=="pb")  c.setPushB=v;
      else if(key=="pt")  c.setPushT=v;
      else if(key=="pm")  c.setPushM=v;
      else if(key=="ma")  c.setMA=(v!=0);
      else if(key=="tp")  c.setTol=v;
      else if(key=="kp")  c.setPts=(v!=0);
      else if(key=="kl")  c.setLines=(v!=0);
      else if(key=="lb")  c.setLabels=(v!=0);
      else if(key=="rn")  c.setReactNew=(v!=0);
      else if(key=="dd")  c.setDelTrace=(v!=0);
     }
   if(c.setPushC<0) c.setPushC=0;
   if(c.setPushB<0) c.setPushB=0;
   if(c.setPushT<0) c.setPushT=0;
   if(c.setPushM<0) c.setPushM=0;
   if(c.setTol<0)   c.setTol=0;
  }

string BuildDesc(const SChannel &c)
  {
   return StringFormat("DEQ a=%d pd=%d pc=%d pb=%d pt=%d pm=%d ma=%d tp=%d kp=%d kl=%d lb=%d rn=%d dd=%d",
                       c.setA?1:0,c.setDead?1:0,c.setPushC,c.setPushB,c.setPushT,c.setPushM,c.setMA?1:0,c.setTol,
                       c.setPts?1:0,c.setLines?1:0,c.setLabels?1:0,
                       c.setReactNew?1:0,c.setDelTrace?1:0);
  }

//+------------------------------------------------------------------+
//| Список каналов                                                   |
//+------------------------------------------------------------------+
int ChFind(const string nm)
  {
   for(int i=0;i<g_nCh;i++)
      if(g_ch[i].name==nm)
         return i;
   return -1;
  }

int ChAdd(const string nm)
  {
   ArrayResize(g_ch,g_nCh+1);
   g_ch[g_nCh].name=nm;
   g_ch[g_nCh].state=CS_OFF;
   g_ch[g_nCh].tA=0; g_ch[g_nCh].tB=0; g_ch[g_nCh].tC=0;
   g_ch[g_nCh].pA=0.0; g_ch[g_nCh].pB=0.0; g_ch[g_nCh].pC=0.0;
   g_ch[g_nCh].pB_at_C=0.0;
   g_ch[g_nCh].up=true;
   g_ch[g_nCh].lastBar=0;
   g_ch[g_nCh].lastTraceBar=0;
   g_ch[g_nCh].lastBT=0; g_ch[g_nCh].lastBP=0.0;
   g_ch[g_nCh].lastDT=0; g_ch[g_nCh].lastDP=0.0;
   g_ch[g_nCh].lastMAT=0; g_ch[g_nCh].lastMAP=0.0;
   g_ch[g_nCh].dmaSum=0.0; g_ch[g_nCh].dmaCnt=0;
   g_ch[g_nCh].fC=false; g_ch[g_nCh].fB=false; g_ch[g_nCh].fTouch=false; g_ch[g_nCh].fTouchM=false;
   g_ch[g_nCh].cntC=0; g_ch[g_nCh].cntB=0; g_ch[g_nCh].cntT=0; g_ch[g_nCh].cntM=0;
   g_ch[g_nCh].labelsDirty=true;
   g_ch[g_nCh].nLB=0; g_ch[g_nCh].nLC=0; g_ch[g_nCh].nLM=0;
   ParseDesc(g_ch[g_nCh]);
   return g_nCh++;
  }

void ChRemove(const int idx)
  {
   DeleteLabels(g_ch[idx].name);
   for(int j=idx;j<g_nCh-1;j++)
      g_ch[j]=g_ch[j+1];
   g_nCh--;
   ArrayResize(g_ch,g_nCh);
  }

//+------------------------------------------------------------------+
//| Пересбор списка: новые каналы с DEQ-кодом, исчезнувшие - вон     |
//+------------------------------------------------------------------+
void ScanChannels()
  {
   //--- исчезнувшие объекты
   for(int i=g_nCh-1;i>=0;i--)
      if(ObjectFind(0,g_ch[i].name)<0)
        {
         if(g_ch[i].setDelTrace)
            ClearTraces(g_ch[i].name);
         ChRemove(i);
        }
   //--- все каналы на графике
   int total=ObjectsTotal(0,-1,OBJ_CHANNEL);
   for(int k=0;k<total;k++)
     {
      string nm=ObjectName(0,k,-1,OBJ_CHANNEL);
      if(nm=="")
         continue;
      string desc=ObjectGetString(0,nm,OBJPROP_TEXT);
      int i=ChFind(nm);
      if(StringFind(desc,"DEQ")==0)
        {
         if(i<0)
            i=ChAdd(nm);
         else
            ParseDesc(g_ch[i]);                      // настройки могли поправить в стандартных свойствах
         if(g_ch[i].setA && g_ch[i].state==CS_OFF)
            ActivateChannel(i);                      // подхват после запуска/перезапуска
        }
      else if(i>=0)
         ChRemove(i);                                // код настроек стерт - больше не сопровождаем
     }
  }

//+------------------------------------------------------------------+
//| Активация канала (в т.ч. с ретро-следом от вертикали С)          |
//+------------------------------------------------------------------+
void ActivateChannel(const int i)
  {
   g_ch[i].state=CS_OFF;
   if(!ReadAnchors(i))
      return;
   if(!GeometryOK(i))
     {
      g_ch[i].state=CS_DEAD;
      Notify(i,"Канал неправильный (условие В/С/А не выполнено). Нарисуйте канал точками: А (низ), В (верх), С (равноудаленная граница).");
      return;
     }

   //--- новая серия или продолжение
   if(g_ch[i].setReactNew)
      ClearTraces(g_ch[i].name);
   int nExisting=RebuildTrace(i);

   bool fresh=(g_ch[i].setReactNew || nExisting==0);
   if(fresh)
     {
      g_ch[i].cntC=0;
      g_ch[i].cntB=0;
      g_ch[i].cntT=0;
      g_ch[i].cntM=0;
      GlobalVariableDel(GVCnt(g_ch[i].name,"C"));
      GlobalVariableDel(GVCnt(g_ch[i].name,"B"));
      GlobalVariableDel(GVCnt(g_ch[i].name,"T"));
      GlobalVariableDel(GVCnt(g_ch[i].name,"M"));
     }
   else
     {
      g_ch[i].cntC=(int)GlobalVariableGet(GVCnt(g_ch[i].name,"C"));
      g_ch[i].cntB=(int)GlobalVariableGet(GVCnt(g_ch[i].name,"B"));
      g_ch[i].cntT=(int)GlobalVariableGet(GVCnt(g_ch[i].name,"T"));
      g_ch[i].cntM=(int)GlobalVariableGet(GVCnt(g_ch[i].name,"M"));
     }

   datetime tCur=iTime(_Symbol,g_tf,0);
   if(tCur==0)
      return;

   //--- стартовая вертикаль: бар якоря С (не раньше А)
   int i0=0;
   if(!fresh && nExisting>0)
      i0=0;                                          // продолжение серии: ретро не нужен
   else
     {
      int iC=iBarShift(_Symbol,g_tf,g_ch[i].tC,false);
      datetime t0=iTime(_Symbol,g_tf,iC);
      if(t0<g_ch[i].tA)
         t0=g_ch[i].tA;
      i0=iBarShift(_Symbol,g_tf,t0,false);
     }

   g_ch[i].fC=false;
   g_ch[i].fB=false;
   g_ch[i].fTouch=false;
   g_ch[i].fTouchM=false;
   g_ch[i].labelsDirty=true;

   //--- РЕТРО: якорь С левее (i0>=2) и начинаем новую серию
   if(i0>=2)
     {
      datetime t0=iTime(_Symbol,g_tf,i0);
      //--- рабочие якоря на стартовой вертикали: экстремумы истории от бара А (не включая его)
      //--- до t0. Нарисованные В/С часто стоят по экстремумам ВСЕГО участка (будущее для t0) -
      //--- их как стартовые брать нельзя, иначе след С сразу идет по крайнему В.
      int iA=iBarShift(_Symbol,g_tf,g_ch[i].tA,false);
      if(iA<0 || iA<=i0)
         iA=i0+1;                                // А не найден или не левее вертикали - окно пустое
      double wB=0.0,wC=0.0;
      datetime tCw=t0;
      bool haveW=false;
      for(int b=iA-1;b>=i0;b--)                 // бары строго после А, до вертикали включительно
        {
         double hi=iHigh(_Symbol,g_tf,b),lo=iLow(_Symbol,g_tf,b);
         if(hi==0.0 && lo==0.0)
            continue;
         if(!haveW)
           {
            wB=g_ch[i].up?hi:lo;
            wC=g_ch[i].up?lo:hi;
            tCw=iTime(_Symbol,g_tf,b);
            haveW=true;
           }
         else if(g_ch[i].up)
           {
            if(hi>wB)
               wB=hi;
            if(lo<wC)
              {
               wC=lo;
               tCw=iTime(_Symbol,g_tf,b);
              }
           }
         else
           {
            if(lo<wB)
               wB=lo;
            if(hi>wC)
              {
               wC=hi;
               tCw=iTime(_Symbol,g_tf,b);
              }
           }
        }
      if(!haveW)
        {
         wB=g_ch[i].pB;                              // окно пустое - нарисованные значения
         wC=g_ch[i].pC;
        }
      MoveB(i,t0,wB);                                // В: время t0, цена = рабочий экстремум к t0
      MoveC(i,tCw,wC);                               // С: бар своего экстремума, цена = рабочий экстремум
      if(!GeometryOK(i))
        {
         g_ch[i].state=CS_DEAD;
         Notify(i,"Канал умер в истории (до стартовой вертикали С). Динамика остановлена.");
         return;
        }
      AddTrace(i,true, t0,wB);                       // В0 = рабочее значение В на t0
      AddTrace(i,false,t0,LineC(i,t0));              // Д0 = граница С на t0
      g_ch[i].lastTraceBar=t0;
      g_ch[i].pB_at_C=g_ch[i].pB;                    // старт: к В нельзя, пока цена не сделает новый экстремум В
      //--- Динамик МА: начальный след от бара А до стартовой вертикали (окно растет)
      if(g_ch[i].setMA)
        {
         int iA0=iBarShift(_Symbol,g_tf,g_ch[i].tA,false);
         if(iA0<0 || iA0<i0)
            iA0=i0;                             // А не найден или правее вертикали - от вертикали
         double s=0.0;
         long   nn=0;
         for(int b=iA0;b>=i0;b--)
           {
            double c=iClose(_Symbol,g_tf,b);
            if(c>0.0)
              {
               s+=c;
               nn++;
              }
            if(nn>0 && iTime(_Symbol,g_tf,b)>g_ch[i].lastMAT)
               AddMATrace(i,iTime(_Symbol,g_tf,b),s/nn);
           }
         g_ch[i].dmaSum=s;
         g_ch[i].dmaCnt=nn;
        }
      int bars=0;
      bool died=false;
      datetime tDeath=0;
      for(int b=i0-1;b>=1;b--)                       // бары от t0+1 до последнего закрытого
        {
         datetime tb=iTime(_Symbol,g_tf,b);
         datetime tp=iTime(_Symbol,g_tf,b+1);        // закрывшийся бар (фиксация следов)
         if(tp>g_ch[i].lastTraceBar)
           {
            AddTrace(i,true, tp,LineAB(i,tp));
            AddTrace(i,false,tp,LineC(i,tp));
            g_ch[i].lastTraceBar=tp;
           }
         //--- Динамик МА: снимок закрывшегося бара + сдвиг С по пробою (заменяет пробой цены С)
         if(g_ch[i].setMA)
           {
            double m=(g_ch[i].dmaCnt>0)? g_ch[i].dmaSum/g_ch[i].dmaCnt : 0.0;
            if(m>0.0)
              {
               if(tp>g_ch[i].lastMAT)
                  AddMATrace(i,tp,m);
               double ex=g_ch[i].up? iLow(_Symbol,g_tf,b+1) : iHigh(_Symbol,g_tf,b+1);
               if((g_ch[i].up && ex<=m-_Point) || (!g_ch[i].up && ex>=m+_Point))
                 {
                  //--- пробой по ЭКСТРЕМУМУ бара (фитиль за МА на >=1 пп):
                  //--- к А - всегда, к В - только после нового экстремума В
                  bool tA=(g_ch[i].up && ex<g_ch[i].pC) || (!g_ch[i].up && ex>g_ch[i].pC);
                  bool tB=(g_ch[i].up && ex>g_ch[i].pC) || (!g_ch[i].up && ex<g_ch[i].pC);
                  bool ext=(g_ch[i].up && g_ch[i].pB>g_ch[i].pB_at_C) || (!g_ch[i].up && g_ch[i].pB<g_ch[i].pB_at_C);
                  if(tA || (tB && ext))
                    {
                     MoveC(i,tp,ex);
                     if(tB && ext)
                        g_ch[i].pB_at_C=g_ch[i].pB;  // ход к В израсходован
                    }
                 }
              }
            double cb=iClose(_Symbol,g_tf,b);        // окно растет: добавляем бар b (А фиксирован)
            if(cb>0.0)
              {
               g_ch[i].dmaSum+=cb;
               g_ch[i].dmaCnt++;
              }
           }
         MoveB(i,tb,g_ch[i].pB);                     // автосдвиг В по времени
         double lo=iLow(_Symbol,g_tf,b);
         double hi=iHigh(_Symbol,g_tf,b);
         if(!g_ch[i].setMA)                          // старое правило: С по пробою цены С
           {
            if(g_ch[i].up)
              {
               if(lo<g_ch[i].pC)
                  MoveC(i,tb,lo);
              }
            else
              {
               if(hi>g_ch[i].pC)
                  MoveC(i,tb,hi);
              }
           }
         if(g_ch[i].up)                              // В по экстремуму бара
           {
            if(hi>g_ch[i].pB)
               MoveB(i,tb,hi);
           }
         else
           {
            if(lo<g_ch[i].pB)
               MoveB(i,tb,lo);
           }
         bars++;
         if(!GeometryOK(i))
           {
            died=true;
            tDeath=tb;
            break;
           }
        }
      if(died)
        {
         g_ch[i].state=CS_DEAD;
         Notify(i,StringFormat("Канал умер в истории (бар %s). Динамика остановлена.",TimeToString(tDeath)));
         return;
        }
      //--- фиксация последнего закрытого бара и выход в реальное время
      datetime tlast=iTime(_Symbol,g_tf,1);
      if(tlast>g_ch[i].lastTraceBar)
        {
         AddTrace(i,true, tlast,LineAB(i,tlast));
         AddTrace(i,false,tlast,LineC(i,tlast));
         g_ch[i].lastTraceBar=tlast;
        }
      if(g_ch[i].setMA)
        {
         double m=(g_ch[i].dmaCnt>0)? g_ch[i].dmaSum/g_ch[i].dmaCnt : 0.0;
         if(m>0.0)
           {
            if(tlast>g_ch[i].lastMAT)
               AddMATrace(i,tlast,m);
            double exf=g_ch[i].up? iLow(_Symbol,g_tf,1) : iHigh(_Symbol,g_tf,1);
            if((g_ch[i].up && exf<=m-_Point) || (!g_ch[i].up && exf>=m+_Point))
              {
               //--- пробой по экстремуму бара (фитиль за МА): к А - всегда, к В - после экстремума В
               bool tA=(g_ch[i].up && exf<g_ch[i].pC) || (!g_ch[i].up && exf>g_ch[i].pC);
               bool tB=(g_ch[i].up && exf>g_ch[i].pC) || (!g_ch[i].up && exf<g_ch[i].pC);
               bool ext=(g_ch[i].up && g_ch[i].pB>g_ch[i].pB_at_C) || (!g_ch[i].up && g_ch[i].pB<g_ch[i].pB_at_C);
               if(tA || (tB && ext))
                 {
                  MoveC(i,tlast,exf);
                  if(tB && ext)
                     g_ch[i].pB_at_C=g_ch[i].pB;     // ход к В израсходован
                 }
              }
           }
        }
      MoveB(i,tCur,g_ch[i].pB);
      g_ch[i].lastBar=tCur;
      g_ch[i].state=CS_ACTIVE;
      Notify(i,StringFormat("Канал принят (%s). Ретро-след: %d баров.",g_ch[i].up?"восходящий":"нисходящий",bars));
      return;
     }

   //--- ОБЫЧНЫЙ СТАРТ / ПРОДОЛЖЕНИЕ (С на текущем/соседнем баре)
   if(g_tBCheck(i,tCur))
      MoveB(i,tCur,g_ch[i].pB);
   g_ch[i].pB_at_C=g_ch[i].pB;                       // старт: к В нельзя, пока цена не сделает новый экстремум В
   g_ch[i].lastBar=tCur;
   g_ch[i].state=CS_ACTIVE;
   //--- Динамик МА: след от бара А до последнего закрытого бара (окно растет)
   if(g_ch[i].setMA)
     {
      int iA0=iBarShift(_Symbol,g_tf,g_ch[i].tA,false);
      if(iA0<1)
         iA0=1;
      double s=0.0;
      long   nn=0;
      for(int b=iA0;b>=1;b--)
        {
         double c=iClose(_Symbol,g_tf,b);
         if(c>0.0)
           {
            s+=c;
            nn++;
           }
         datetime tm=iTime(_Symbol,g_tf,b);
         if(nn>0 && tm>g_ch[i].lastMAT)
            AddMATrace(i,tm,s/nn);
        }
     }
   if(fresh)
     {
      AddTrace(i,true, tCur,g_ch[i].pB);             // В0 = стартовое значение В
      AddTrace(i,false,tCur,LineC(i,tCur));          // Д0 = граница С на t0
      g_ch[i].lastTraceBar=tCur;
      Notify(i,StringFormat("Канал принят (%s). Динамика и автосдвиг запущены.",g_ch[i].up?"восходящий":"нисходящий"));
     }
   else
      Notify(i,StringFormat("Канал принят (%s). Продолжение серии следов.",g_ch[i].up?"восходящий":"нисходящий"));
  }

//--- В правее бара tCur? (защита от сдвига назад)
bool g_tBCheck(const int i,const datetime tCur)
  {
   return (g_ch[i].tB==0 || tCur>=g_ch[i].tB);
  }

//+------------------------------------------------------------------+
//| Канал умер                                                       |
//+------------------------------------------------------------------+
void ChannelDead(const int i)
  {
   g_ch[i].state=CS_DEAD;
   if(g_ch[i].setDead)
      Notify(i,"Канал умер (условие В/С/А нарушено). Дальше - действия оператора.");
   else
      Print("[Канал ",g_ch[i].name,"] умер, автоматика остановлена.");
  }

//+------------------------------------------------------------------+
//| Новый бар: фиксация следов (до сдвига) + автосдвиг В по времени  |
//+------------------------------------------------------------------+
void OnNewBar(const int i)
  {
   datetime tCur=iTime(_Symbol,g_tf,0);
   datetime tClosed=iTime(_Symbol,g_tf,1);
   if(tClosed==0)
      tClosed=g_ch[i].lastBar;

   if(tClosed>g_ch[i].lastTraceBar)
     {
      AddTrace(i,true, tClosed,LineAB(i,tClosed));
      AddTrace(i,false,tClosed,LineC(i,tClosed));
      g_ch[i].lastTraceBar=tClosed;
     }

   //--- Динамик МА: снимок закрытого бара + сдвиг С по пробою средней
   if(g_ch[i].setMA)
     {
      double m=DMAValue(i,1);
      if(m>0.0)
        {
         if(tClosed>g_ch[i].lastMAT)
            AddMATrace(i,tClosed,m);
         double exn=g_ch[i].up? iLow(_Symbol,g_tf,1) : iHigh(_Symbol,g_tf,1);
         if((g_ch[i].up && exn<=m-_Point) || (!g_ch[i].up && exn>=m+_Point))
           {
            //--- пробой по экстремуму бара (фитиль за МА): к А - всегда, к В - после экстремума В
            bool tA=(g_ch[i].up && exn<g_ch[i].pC) || (!g_ch[i].up && exn>g_ch[i].pC);
            bool tB=(g_ch[i].up && exn>g_ch[i].pC) || (!g_ch[i].up && exn<g_ch[i].pC);
            bool ext=(g_ch[i].up && g_ch[i].pB>g_ch[i].pB_at_C) || (!g_ch[i].up && g_ch[i].pB<g_ch[i].pB_at_C);
            if(tA || (tB && ext))
              {
               MoveC(i,tClosed,exn);
               if(tB && ext)
                  g_ch[i].pB_at_C=g_ch[i].pB;        // ход к В израсходован
               if(g_ch[i].setPushC>0 && g_ch[i].cntC<g_ch[i].setPushC)
                 {
                  g_ch[i].cntC++;
                  GlobalVariableSet(GVCnt(g_ch[i].name,"C"),g_ch[i].cntC);
                  Notify(i,StringFormat("Перерисовка C по пробою Динамик МА (экстремум): экстр=%s MA=%s C=%s",
                                        DoubleToString(exn,_Digits),DoubleToString(m,_Digits),DoubleToString(exn,_Digits)));
                 }
              }
           }
        }
      if(!GeometryOK(i))
        {
         ChannelDead(i);
         return;
        }
     }

   if(tCur>0)
     {
      MoveB(i,tCur,g_ch[i].pB);
      g_ch[i].lastBar=tCur;
     }

   g_ch[i].fC=false;
   g_ch[i].fB=false;
   g_ch[i].fTouch=false;
   g_ch[i].fTouchM=false;
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Потиковая логика внутри текущего бара                            |
//| Сравнение бид - с ЦЕНАМИ ТОЧЕК В и С; касание - по ЛИНИИ С.      |
//| Не более одного пуша на событие в пределах бара, всего не более  |
//| заданного числа пушей (сброс - новая серия).                     |
//+------------------------------------------------------------------+
void OnTickCheck(const int i)
  {
   if(g_ch[i].lastBar==0)
      return;
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(bid<=0.0)
      return;
   datetime tCur=g_ch[i].lastBar;
   double tol=(double)MathMax(0,g_ch[i].setTol)*_Point;
   bool changed=false;

   if(g_ch[i].up)
     {
      if(!g_ch[i].setMA && bid<g_ch[i].pC)
        {
         if(g_ch[i].setPushC>0 && g_ch[i].cntC<g_ch[i].setPushC && !g_ch[i].fC)
           {
            g_ch[i].fC=true;
            g_ch[i].cntC++;
            GlobalVariableSet(GVCnt(g_ch[i].name,"C"),g_ch[i].cntC);
            Notify(i,StringFormat("Перерисовка точки C вниз: bid=%s",DoubleToString(bid,_Digits)));
           }
         MoveC(i,tCur,bid);
         changed=true;
        }
      else if(g_ch[i].setPushT>0 && g_ch[i].cntT<g_ch[i].setPushT && !g_ch[i].fTouch)
        {
         double lineC=LineC(i,tCur);
         if(bid>=lineC && (bid-lineC)<=tol)
           {
            g_ch[i].fTouch=true;
            g_ch[i].cntT++;
            GlobalVariableSet(GVCnt(g_ch[i].name,"T"),g_ch[i].cntT);
            Notify(i,StringFormat("Касание линии C: bid=%s",DoubleToString(bid,_Digits)));
           }
        }
      else if(g_ch[i].setMA && g_ch[i].setPushM>0 && g_ch[i].cntM<g_ch[i].setPushM &&
              !g_ch[i].fTouchM && g_ch[i].lastMAP>0.0 && MathAbs(bid-g_ch[i].lastMAP)<=tol)
        {
         g_ch[i].fTouchM=true;
         g_ch[i].cntM++;
         GlobalVariableSet(GVCnt(g_ch[i].name,"M"),g_ch[i].cntM);
         Notify(i,StringFormat("Касание Динамик МА: bid=%s MA=%s",
                               DoubleToString(bid,_Digits),DoubleToString(g_ch[i].lastMAP,_Digits)));
        }
      if(bid>g_ch[i].pB)
        {
         if(g_ch[i].setPushB>0 && g_ch[i].cntB<g_ch[i].setPushB && !g_ch[i].fB)
           {
            g_ch[i].fB=true;
            g_ch[i].cntB++;
            GlobalVariableSet(GVCnt(g_ch[i].name,"B"),g_ch[i].cntB);
            Notify(i,StringFormat("Перерисовка точки B вверх: bid=%s",DoubleToString(bid,_Digits)));
           }
         MoveB(i,tCur,bid);
         changed=true;
        }
     }
   else
     {
      if(!g_ch[i].setMA && bid>g_ch[i].pC)
        {
         if(g_ch[i].setPushC>0 && g_ch[i].cntC<g_ch[i].setPushC && !g_ch[i].fC)
           {
            g_ch[i].fC=true;
            g_ch[i].cntC++;
            GlobalVariableSet(GVCnt(g_ch[i].name,"C"),g_ch[i].cntC);
            Notify(i,StringFormat("Перерисовка точки C вверх: bid=%s",DoubleToString(bid,_Digits)));
           }
         MoveC(i,tCur,bid);
         changed=true;
        }
      else if(g_ch[i].setPushT>0 && g_ch[i].cntT<g_ch[i].setPushT && !g_ch[i].fTouch)
        {
         double lineC=LineC(i,tCur);
         if(bid<=lineC && (lineC-bid)<=tol)
           {
            g_ch[i].fTouch=true;
            g_ch[i].cntT++;
            GlobalVariableSet(GVCnt(g_ch[i].name,"T"),g_ch[i].cntT);
            Notify(i,StringFormat("Касание линии C: bid=%s",DoubleToString(bid,_Digits)));
           }
        }
      else if(g_ch[i].setMA && g_ch[i].setPushM>0 && g_ch[i].cntM<g_ch[i].setPushM &&
              !g_ch[i].fTouchM && g_ch[i].lastMAP>0.0 && MathAbs(bid-g_ch[i].lastMAP)<=tol)
        {
         g_ch[i].fTouchM=true;
         g_ch[i].cntM++;
         GlobalVariableSet(GVCnt(g_ch[i].name,"M"),g_ch[i].cntM);
         Notify(i,StringFormat("Касание Динамик МА: bid=%s MA=%s",
                               DoubleToString(bid,_Digits),DoubleToString(g_ch[i].lastMAP,_Digits)));
        }
      if(bid<g_ch[i].pB)
        {
         if(g_ch[i].setPushB>0 && g_ch[i].cntB<g_ch[i].setPushB && !g_ch[i].fB)
           {
            g_ch[i].fB=true;
            g_ch[i].cntB++;
            GlobalVariableSet(GVCnt(g_ch[i].name,"B"),g_ch[i].cntB);
            Notify(i,StringFormat("Перерисовка точки B вниз: bid=%s",DoubleToString(bid,_Digits)));
           }
         MoveB(i,tCur,bid);
         changed=true;
        }
     }

   if(!GeometryOK(i))
     {
      ChannelDead(i);
      return;
     }
   if(changed)
      ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Статус всех каналов (комментарий в углу графика)                 |
//+------------------------------------------------------------------+
void UpdateStatusComment()
  {
   string s="";
   if(g_nCh>0)
     {
      s="Динамические каналы:\n";
      for(int i=0;i<g_nCh;i++)
        {
         string st="?";
         if(g_ch[i].state==CS_OFF)
            st="динамика выкл";
         else if(g_ch[i].state==CS_ACTIVE)
            st="работает";
         else if(g_ch[i].state==CS_PAUSED)
            st="пауза (ручная правка)";
         else if(g_ch[i].state==CS_DEAD)
            st="умер";
         s+=StringFormat("  %s — %s\n",g_ch[i].name,st);
        }
     }
   if(s!=g_lastStatus)
     {
      Comment(s);
      g_lastStatus=s;
     }
  }

//+------------------------------------------------------------------+
//| Основной цикл                                                    |
//+------------------------------------------------------------------+
void DoWork()
  {
   ScanChannels();
   for(int i=0;i<g_nCh;i++)
     {
      if(g_ch[i].state==CS_ACTIVE)
        {
         if(ObjectFind(0,g_ch[i].name)<0)
           {
            g_ch[i].state=CS_OFF;
            continue;
           }
         datetime t0=iTime(_Symbol,g_tf,0);
         if(t0>0)
           {
            if(g_ch[i].lastBar==0)
               g_ch[i].lastBar=t0;
            else if(t0!=g_ch[i].lastBar)
               OnNewBar(i);
           }
         OnTickCheck(i);
        }
      UpdateLabels(i);
     }
   UpdateStatusComment();
  }

//+------------------------------------------------------------------+
//| ОКНО СВОЙСТВ ДИНАМИКИ (объекты графика)                          |
//+------------------------------------------------------------------+
#define DEQ_WIN_X 140
#define DEQ_WIN_Y 70
#define DEQ_WIN_W 330
#define DEQ_WIN_H 414

string WName(const string id)
  {
   return StringFormat("DEQW_%s_%I64d",id,g_runid);
  }

void WinFont(const string nm,const int fs,const color clr)
  {
   ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,fs);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,clr);
   ObjectSetString(0,nm,OBJPROP_FONT,"Arial");
  }

void WinLabel(const string id,const string txt,const int x,const int y,const int fs,const color clr)
  {
   string nm=WName(id);
   if(ObjectFind(0,nm)<0)
     {
      ObjectCreate(0,nm,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,nm,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,nm,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,nm,OBJPROP_ZORDER,10);
     }
   ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,y);
   WinFont(nm,fs,clr);
   ObjectSetString(0,nm,OBJPROP_TEXT,txt);
  }

void WinCheck(const string id,const string txt,const int y,const bool checked)
  {
   string nm=WName(id);
   if(ObjectFind(0,nm)<0)
     {
      ObjectCreate(0,nm,OBJ_BUTTON,0,0,0);
      ObjectSetInteger(0,nm,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,nm,OBJPROP_XSIZE,18);
      ObjectSetInteger(0,nm,OBJPROP_YSIZE,18);
      ObjectSetString(0,nm,OBJPROP_TEXT,"");
      ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,12);
      ObjectSetString(0,nm,OBJPROP_FONT,"Arial Black");
      ObjectSetInteger(0,nm,OBJPROP_COLOR,clrBlack);
      ObjectSetInteger(0,nm,OBJPROP_BGCOLOR,clrWhite);
      ObjectSetInteger(0,nm,OBJPROP_BORDER_COLOR,clrGray);
      ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,nm,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,nm,OBJPROP_ZORDER,11);
     }
   ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,DEQ_WIN_X+12);
   ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,nm,OBJPROP_STATE,checked);
   ObjectSetString(0,nm,OBJPROP_TEXT,checked?"\x2713":"");   // галка видна четче, чем нажатая кнопка
   WinLabel("L"+id,txt,DEQ_WIN_X+36,y,9,clrSilver);
  }

void WinRow(const string id,const string txt,const int y,const int value)
  {
   WinLabel("L"+id,txt,DEQ_WIN_X+12,y+2,9,clrSilver);
   string nm=WName(id);
   if(ObjectFind(0,nm)<0)
     {
      ObjectCreate(0,nm,OBJ_EDIT,0,0,0);
      ObjectSetInteger(0,nm,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,nm,OBJPROP_XSIZE,64);
      ObjectSetInteger(0,nm,OBJPROP_YSIZE,20);
      ObjectSetInteger(0,nm,OBJPROP_COLOR,clrBlack);
      ObjectSetInteger(0,nm,OBJPROP_BGCOLOR,clrWhite);
      ObjectSetInteger(0,nm,OBJPROP_BORDER_COLOR,clrGray);
      ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,nm,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,nm,OBJPROP_ZORDER,11);
     }
   ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,DEQ_WIN_X+DEQ_WIN_W-80);
   ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,nm,OBJPROP_TEXT,IntegerToString(value));
  }

void WinButton(const string id,const string txt,const int x,const int y,const int w)
  {
   string nm=WName(id);
   if(ObjectFind(0,nm)<0)
     {
      ObjectCreate(0,nm,OBJ_BUTTON,0,0,0);
      ObjectSetInteger(0,nm,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,nm,OBJPROP_YSIZE,22);
      ObjectSetInteger(0,nm,OBJPROP_COLOR,clrBlack);
      ObjectSetInteger(0,nm,OBJPROP_BGCOLOR,clrGainsboro);
      ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,nm,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,nm,OBJPROP_ZORDER,11);
     }
   ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,nm,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,nm,OBJPROP_STATE,false);
   ObjectSetString(0,nm,OBJPROP_TEXT,txt);
  }

void DestroySettingsWindow()
  {
   if(!g_dlgOpen)
      return;
   string pref="DEQW_";
   for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--)
     {
      string nm=ObjectName(0,i,-1,-1);
      if(StringFind(nm,"DEQW_")==0)
         ObjectDelete(0,nm);
     }
   g_dlgOpen=false;
   g_dlgChanName="";
   ChartRedraw();
  }

void CreateSettingsWindow(const string chanName)
  {
   DestroySettingsWindow();
   //--- настройки канала (или дефолты для нового)
   SChannel tmp;
   tmp.name=chanName;
   int i=ChFind(chanName);
   if(i>=0)
      tmp=g_ch[i];
   else
      ParseDesc(tmp);

   //--- фон
   string bg=WName("BG");
   ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bg,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,DEQ_WIN_X);
   ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,DEQ_WIN_Y);
   ObjectSetInteger(0,bg,OBJPROP_XSIZE,DEQ_WIN_W);
   ObjectSetInteger(0,bg,OBJPROP_YSIZE,DEQ_WIN_H);
   ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,C'43,43,46');
   ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,bg,OBJPROP_COLOR,clrDimGray);
   ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,bg,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,bg,OBJPROP_ZORDER,9);

   //--- заголовок
   string ttl=chanName;
   if(StringLen(ttl)>42)
      ttl=StringSubstr(ttl,0,42)+"...";
   WinLabel("T","Канал: "+ttl,DEQ_WIN_X+12,DEQ_WIN_Y+8,10,clrWhite);
   string st="динамика выкл";
   if(i>=0)
     {
      if(g_ch[i].state==CS_ACTIVE)      st="работает";
      else if(g_ch[i].state==CS_PAUSED) st="пауза (ручная правка)";
      else if(g_ch[i].state==CS_DEAD)   st="умер";
     }
   WinLabel("ST","Состояние: "+st,DEQ_WIN_X+12,DEQ_WIN_Y+28,9,clrKhaki);

   int y=DEQ_WIN_Y+52;
   int dy=24;
   WinCheck("chka","Активность динамики",y,tmp.setA);               y+=dy;
   WinCheck("chkd","Пуш: канал умер",y,tmp.setDead);                y+=dy;
   WinRow("edtpc","Пуши: перерисовка C",y,tmp.setPushC);            y+=dy;
   WinRow("edtpb","Пуши: перерисовка B",y,tmp.setPushB);            y+=dy;
   WinRow("edtpt","Пуши: касание линии C",y,tmp.setPushT);          y+=dy;
   WinRow("edttp","Допуск касания (пункты)",y,tmp.setTol);          y+=dy;
   WinCheck("chkm","Динамик МА: след, касание, сдвиг C",y,tmp.setMA);          y+=dy;
   WinRow("edtpm","Пуши: касание Динамик МА",y,tmp.setPushM);               y+=dy;
   WinCheck("chkp","Следы: точки",y,tmp.setPts);                    y+=dy;
   WinCheck("chkl","Следы: линии",y,tmp.setLines);                  y+=dy;
   WinCheck("chkb","Подписи А/В/С",y,tmp.setLabels);                y+=dy;
   WinCheck("chkr","Реактивация: стереть и начать заново",y,tmp.setReactNew); y+=dy;
   WinCheck("chkx","Удаление канала: стереть следы",y,tmp.setDelTrace);      y+=dy+8;

   WinButton("btnOK","Применить",DEQ_WIN_X+12,y,100);
   WinButton("btnCC","Закрыть",DEQ_WIN_X+124,y,80);

   g_dlgChanName=chanName;
   g_dlgOpen=true;
   ChartRedraw();
  }

bool WinGetCheck(const string id)
  {
   return (bool)ObjectGetInteger(0,WName(id),OBJPROP_STATE);
  }

int WinGetEditInt(const string id,const int def)
  {
   string s=ObjectGetString(0,WName(id),OBJPROP_TEXT);
   StringTrimLeft(s);
   StringTrimRight(s);
   if(s=="")
      return def;
   int v=(int)StringToInteger(s);
   if(v<0)
      v=0;
   return v;
  }

void ApplySettingsWindow()
  {
   string nm=g_dlgChanName;
   if(nm=="" || ObjectFind(0,nm)<0)
     {
      DestroySettingsWindow();
      return;
     }
   int i=ChFind(nm);
   if(i<0)
      i=ChAdd(nm);
   bool maOn=WinGetCheck("chkm");
   bool maChanged=(maOn!=g_ch[i].setMA);
   g_ch[i].setA=WinGetCheck("chka");
   g_ch[i].setDead=WinGetCheck("chkd");
   g_ch[i].setPushC=WinGetEditInt("edtpc",1);
   g_ch[i].setPushB=WinGetEditInt("edtpb",1);
   g_ch[i].setPushT=WinGetEditInt("edtpt",1);
   g_ch[i].setTol=WinGetEditInt("edttp",10);
   g_ch[i].setMA=WinGetCheck("chkm");
   g_ch[i].setPushM=WinGetEditInt("edtpm",1);
   g_ch[i].setPts=WinGetCheck("chkp");
   g_ch[i].setLines=WinGetCheck("chkl");
   g_ch[i].setLabels=WinGetCheck("chkb");
   g_ch[i].setReactNew=WinGetCheck("chkr");
   g_ch[i].setDelTrace=WinGetCheck("chkx");
   //--- настройки пишем в описание объекта (живут в самом канале)
   ObjectSetString(0,nm,OBJPROP_TEXT,BuildDesc(g_ch[i]));
   //--- состояние
   if(g_ch[i].setA && maChanged && maOn)
     {
      //--- МА только что включили: пересобираем серию целиком,
      //--- чтобы получить ретро-след МА и исторические сдвиги С
      ClearTraces(g_ch[i].name);
      ActivateChannel(i);
     }
   else if(g_ch[i].setA && g_ch[i].state!=CS_ACTIVE)
      ActivateChannel(i);
   else if(g_ch[i].setA && maChanged && !maOn)
      ClearMATrace(i);                          // МА выключили: стираем след, вернется старое правило С
   else if(!g_ch[i].setA)
      g_ch[i].state=CS_OFF;
   DestroySettingsWindow();
  }

//+------------------------------------------------------------------+
//| Инициализация                                                    |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_tf=(InpWorkTF==PERIOD_CURRENT)?(ENUM_TIMEFRAMES)_Period:InpWorkTF;
   g_runid=(long)TimeLocal()*1000+(long)(GetTickCount()%1000);
   g_nCh=0;
   ArrayResize(g_ch,0);
   g_dlgOpen=false;
   g_dlgChanName="";
   g_lastStatus="";
   IndicatorSetString(INDICATOR_SHORTNAME,"DynamicEqChannel");
   //--- подчистить объекты старых версий (панели, статусы, следы v1.xx)
   for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--)
     {
      string nm=ObjectName(0,i,-1,-1);
      if(StringFind(nm,"DEQ_BTN")==0 || StringFind(nm,"DEQ_ST_")==0 ||
         StringFind(nm,"DEQ_LBL_")==0 || StringFind(nm,"DEQ_PB_")==0 ||
         StringFind(nm,"DEQ_PC_")==0 || StringFind(nm,"DEQ_LB_")==0 ||
         StringFind(nm,"DEQ_LC_")==0)
         ObjectDelete(0,nm);
     }
   EventSetTimer(1);
   ScanChannels();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Деинициализация                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   DestroySettingsWindow();
   Comment("");
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Расчет индикатора (тики)                                         |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
  {
   DoWork();
   return rates_total;
  }

//+------------------------------------------------------------------+
//| Таймер (страховка от "тихих" баров и подхват каналов)            |
//+------------------------------------------------------------------+
void OnTimer()
  {
   DoWork();
  }

//+------------------------------------------------------------------+
//| События графика                                                  |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   //--- клики по элементам окна свойств динамики
   if(id==CHARTEVENT_OBJECT_CLICK && StringFind(sparam,"DEQW_")==0)
     {
      if(sparam==WName("btnOK"))
         ApplySettingsWindow();
      else if(sparam==WName("btnCC"))
         DestroySettingsWindow();
      else
        {
         //--- чекбокс: терминал сам переключил STATE - перерисовать галку
         if((ENUM_OBJECT)ObjectGetInteger(0,sparam,OBJPROP_TYPE)==OBJ_BUTTON)
           {
            bool st=(bool)ObjectGetInteger(0,sparam,OBJPROP_STATE);
            ObjectSetString(0,sparam,OBJPROP_TEXT,st?"\x2713":"");
            ChartRedraw();
           }
        }
      return;
     }

   //--- клик по каналу: открыть окно свойств динамики
   if(id==CHARTEVENT_OBJECT_CLICK)
     {
      if(ObjectFind(0,sparam)>=0 &&
         (ENUM_OBJECT)ObjectGetInteger(0,sparam,OBJPROP_TYPE)==OBJ_CHANNEL)
         CreateSettingsWindow(sparam);
      return;
     }

   if(id==CHARTEVENT_OBJECT_CREATE)
     {
      if((ENUM_OBJECT)ObjectGetInteger(0,sparam,OBJPROP_TYPE)==OBJ_CHANNEL)
         ScanChannels();
      return;
     }

   if(id==CHARTEVENT_OBJECT_DELETE)
     {
      int i=ChFind(sparam);
      if(i>=0)
        {
         if(g_ch[i].setDelTrace)
            ClearTraces(g_ch[i].name);               // иначе следы остаются снимком
         ChRemove(i);
         UpdateStatusComment();
        }
      return;
     }

   if(id==CHARTEVENT_OBJECT_DRAG || id==CHARTEVENT_OBJECT_CHANGE)
     {
      int i=ChFind(sparam);
      if(i<0)
         return;
      //--- запомнить состояние до события
      datetime oA=g_ch[i].tA,oB=g_ch[i].tB,oC=g_ch[i].tC;
      double  qA=g_ch[i].pA,qB=g_ch[i].pB,qC=g_ch[i].pC;
      bool oldA=g_ch[i].setA;
      //--- перечитать настройки (могли править описание в стандартных свойствах)
      ParseDesc(g_ch[i]);
      bool anchors=ReadAnchors(i);
      bool moved=(!anchors || oA!=g_ch[i].tA || oB!=g_ch[i].tB || oC!=g_ch[i].tC ||
                  qA!=g_ch[i].pA || qB!=g_ch[i].pB || qC!=g_ch[i].pC);
      if(moved && g_ch[i].state==CS_ACTIVE)
        {
         //--- мягкая блокировка: ручная правка активного канала -> пауза
         if(anchors && GeometryOK(i))
            g_ch[i].labelsDirty=true;
         g_ch[i].state=CS_PAUSED;
         Notify(i,"Динамика приостановлена: канал изменен вручную. Кликните канал и нажмите \"Применить\" для возобновления.");
        }
      else if(!oldA && g_ch[i].setA && g_ch[i].state!=CS_ACTIVE)
         ActivateChannel(i);                         // активность включили текстом в описании
      else if(oldA && !g_ch[i].setA)
         g_ch[i].state=CS_OFF;
      UpdateStatusComment();
      return;
     }
  }
//+------------------------------------------------------------------+
