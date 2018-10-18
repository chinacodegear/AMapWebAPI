unit UnitAMapWebAPI;

interface

uses
  System.SysUtils, System.Classes, IPPeerClient, FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Param, FireDAC.Stan.Error, FireDAC.DatS,
  FireDAC.Phys.Intf, FireDAC.DApt.Intf, Data.DB, FireDAC.Comp.DataSet, FireDAC.Comp.Client, REST.Response.Adapter, REST.Client, Data.Bind.Components,
  Data.Bind.ObjectScope;

type
  TDMAMapWebAPI = class(TDataModule)
    RESTClient: TRESTClient;
    RESTRequest: TRESTRequest;
    RESTResponse: TRESTResponse;
    RESTResponseDataSetAdapter: TRESTResponseDataSetAdapter;
    FDMemTable: TFDMemTable;
    FDMemTable2: TFDMemTable;
    procedure DataModuleCreate(Sender: TObject);
  private
    CoordConvertURL: string;
    RevGeocodingURL: string;
    TruckRouteURL: string;
    DistanceURL: string;
    WeatherInfoURL: string;
    GeofenceMetaURL: string;
    GeofenceStatusURL: string;
    A38, A44: string;
    procedure ClearStatus;
  public
    WebApiKey: string;
    //
    function Gps2AMap(const GpsLng, GpsLat: string): string; // 坐标转换API
    function RevGeocoding(const AMapLng, AMapLat: string): string; // 根据经纬度获取地址信息
    function TruckRoutePlan(const BeginLng, BeginLat, EndLng, EndLat, ADiu, Aheight, Awidth, Aload, Aweight, Aaxis, Aprovince, Anumber, Astrategy,
      Asize: string): string; // 货车运输计划数据
    function Distance(const BeginLng, BeginLat, EndLng, EndLat, AType: string): string; // 距离量算
    function WeatherInfo(const Acity, Aextensions: string): string; // 天气查询
    function GeofenceQuery(const Agid: string = ''): string; // 查询围栏
    function GeofenceDelete(const Agid: string): string; // 删除围栏
    function GeofenceCheckin(const ADiu, AMapLng, AMapLat, Agid: string): string; // 围栏设备监控
  end;

var
  DMAMapWebAPI: TDMAMapWebAPI;

implementation

uses System.JSON, System.DateUtils, REST.Types;

{%CLASSGROUP 'FMX.Controls.TControl'}
{$R *.dfm}

function TDMAMapWebAPI.GeofenceCheckin(const ADiu, AMapLng, AMapLat, Agid: string): string;
var
  URL, diu, locations: string;
begin
  //
  ClearStatus;
  URL := Concat(GeofenceStatusURL, 'key=', WebApiKey, A38);
  diu := Concat('diu=', ADiu, A38);
  locations := Concat('locations=', AMapLng, A44, AMapLat);
  URL := Concat(URL, diu, locations, A44, DateTimeToUnix(Now).ToString);

  RESTClient.BaseURL := URL;
  RESTRequest.Method := TRESTRequestMethod.rmGET;
  RESTRequest.Execute;

  Result := FDMemTable.FieldByName('errmsg').AsString;
  if (Result = 'OK') then
  begin
    RESTResponse.RootElement := 'data.fencing_event_list';
    if (FDMemTable.RecordCount = 1) then
    begin
      if (FDMemTable.FieldByName('client_status').AsString = 'in') then
      begin
        RESTResponse.RootElement := 'data.fencing_event_list[0].fence_info';
        if Agid = FDMemTable.FieldByName('fence_gid').AsString then
        begin
          Exit('1');
        end
        else
        begin
          Exit('0');
        end;
      end;
    end
    else
    begin
      Exit('0'); // 不在围栏内
    end;
  end;
end;

function TDMAMapWebAPI.GeofenceDelete(const Agid: string): string;
var
  URL, gid: string;
begin
  //
  ClearStatus;
  URL := Concat(GeofenceMetaURL, 'key=', WebApiKey, A38);
  gid := Concat('gid=', Agid);
  URL := Concat(URL, gid);

  RESTClient.BaseURL := URL;
  RESTRequest.Method := TRESTRequestMethod.rmDELETE;
  RESTRequest.Execute;

  Result := FDMemTable.FieldByName('errmsg').AsString;
  if (Result = 'OK') then
  begin
    RESTResponse.RootElement := 'data';
    Result := FDMemTable.FieldByName('message').AsString;
  end;
end;

function TDMAMapWebAPI.GeofenceQuery(const Agid: string): string;
var
  URL, gid: string;
begin
  // 返回 Key 所创建的 所有 或 某个 围栏信息 errcode
  ClearStatus;
  URL := Concat(GeofenceMetaURL, 'key=', WebApiKey, A38);
  gid := Concat('gid=', Agid);
  URL := Concat(URL, gid);

  RESTClient.BaseURL := URL;
  RESTRequest.Method := TRESTRequestMethod.rmGET;
  RESTRequest.Execute;

  Result := FDMemTable.FieldByName('errmsg').AsString;
  if (Result = 'OK') then
  begin
    RESTResponse.RootElement := 'data.rs_list';
  end;
end;

function TDMAMapWebAPI.Gps2AMap(const GpsLng, GpsLat: string): string;
var
  URL, locations: string;
begin
  // 回返 longitude,latitude
  ClearStatus;
  URL := Concat(CoordConvertURL, 'key=', WebApiKey, A38, 'coordsys=gps', A38);
  locations := Concat('locations=', GpsLng, A44, GpsLat);
  URL := Concat(URL, locations);
  RESTClient.BaseURL := URL;
  RESTRequest.Method := TRESTRequestMethod.rmGET;
  RESTRequest.Execute;

  if (FDMemTable.FieldByName('status').AsInteger = 1) then
  begin
    Exit(FDMemTable.FieldByName('locations').AsString);
  end
  else
  begin
    Exit(FDMemTable.FieldByName('info').AsString);
  end;
end;

function TDMAMapWebAPI.TruckRoutePlan(const BeginLng, BeginLat, EndLng, EndLat, ADiu, Aheight, Awidth, Aload, Aweight, Aaxis, Aprovince, Anumber,
  Astrategy, Asize: string): string;
var
  URL, origin, destination, diu, height, width, load, weight, axis, province, number, strategy, size, showpolyline: string;
begin
  { Astrategy
    1---“躲避拥堵”
    2---“不走高速”
    3---“避免收费”
    4---“躲避拥堵&不走高速”
    5---“避免收费&不走高速”  //3+2
    6---“躲避拥堵&避免收费”
    7---“躲避拥堵&避免收费&不走高速”
    8---“高速优先” //
    9---“躲避拥堵&高速优先” //1+8
  }
  // 回返 获取状态, FDMemTable切换到 data.route.paths
  ClearStatus;
  URL := Concat(TruckRouteURL, 'key=', WebApiKey, A38);
  origin := Concat('origin=', BeginLng, A44, BeginLat, A38);
  destination := Concat('destination=', EndLng, A44, EndLat, A38);
  diu := Concat('diu=', ADiu, A38);
  height := Concat('height=', Aheight, A38);
  width := Concat('width=', Awidth, A38);
  load := Concat('load=', Aload, A38);
  weight := Concat('weight=', Aweight, A38);
  axis := Concat('axis=', Aaxis, A38);
  province := Concat('province=', Aprovince, A38);
  number := Concat('number=', Anumber, A38);
  strategy := Concat('strategy=', Astrategy, A38);
  size := Concat('size=', Asize, A38);
  showpolyline := Concat('showpolyline=', '0');

  URL := Concat(URL, origin, destination, diu, height, width, load, weight, axis, province, number, strategy, size, showpolyline);
  RESTClient.BaseURL := URL;
  RESTRequest.Method := TRESTRequestMethod.rmGET;
  RESTRequest.Execute;
  Result := FDMemTable.FieldByName('errmsg').AsString;
  if Result = 'OK' then
  begin
    RESTResponse.RootElement := 'data.route.paths';
  end;
end;

function TDMAMapWebAPI.WeatherInfo(const Acity, Aextensions: string): string;
var
  URL, city, extensions: string;
begin
  // 返回 天气信息,切换到 lives 或 forecasts[0].casts
  // 可选值：base/all base:返回实况天气 all:返回预报天气
  ClearStatus;
  URL := Concat(WeatherInfoURL, 'key=', WebApiKey, A38);
  city := Concat('city=', Acity, A38);
  extensions := Concat('extensions=', Aextensions);
  URL := Concat(URL, city, extensions);

  RESTClient.BaseURL := URL;
  RESTRequest.Method := TRESTRequestMethod.rmGET;
  RESTRequest.Execute;

  if (FDMemTable.FieldByName('status').AsInteger = 1) then
  begin
    if LowerCase(Aextensions) = 'base' then
    begin
      RESTResponse.RootElement := 'lives';
      Exit(FDMemTable.FieldByName('weather').AsString);
    end
    else
    begin
      RESTResponse.RootElement := 'forecasts[0].casts';
      Exit(FDMemTable.FieldByName('dayweather').AsString);
    end;
  end
  else
  begin
    Exit(FDMemTable.FieldByName('info').AsString);
  end;
end;

function TDMAMapWebAPI.RevGeocoding(const AMapLng, AMapLat: string): string;
var
  URL, Location: string;
begin
  // 回返详细地址, FDMemTable切换到 regeocode.addressComponent
  ClearStatus;
  URL := Concat(RevGeocodingURL, 'key=', WebApiKey, A38);
  Location := Concat('location=', AMapLng, A44, AMapLat);
  URL := Concat(URL, Location);

  RESTClient.BaseURL := URL;
  RESTRequest.Method := TRESTRequestMethod.rmGET;
  RESTRequest.Execute;

  if (FDMemTable.FieldByName('status').AsInteger = 1) then
  begin
    RESTResponse.RootElement := 'regeocode';
    Result := FDMemTable.FieldByName('formatted_address').AsString;
    RESTResponse.RootElement := 'regeocode.addressComponent';
  end
  else
  begin
    Exit(FDMemTable.FieldByName('info').AsString);
  end;
end;

procedure TDMAMapWebAPI.ClearStatus;
begin
  RESTResponse.ResetToDefaults;
  RESTResponseDataSetAdapter.ClearDataSet;
  RESTResponse.RootElement := EmptyStr;
end;

procedure TDMAMapWebAPI.DataModuleCreate(Sender: TObject);
begin
  A38 := #38; // &
  A44 := #44; // ,
  WebApiKey := '02deb20436dcd7b9fc25a2c9da700db';
  CoordConvertURL := 'https://restapi.amap.com/v3/assistant/coordinate/convert?';
  RevGeocodingURL := 'https://restapi.amap.com/v3/geocode/regeo?';
  TruckRouteURL := 'https://restapi.amap.com/v4/direction/truck?';
  DistanceURL := 'https://restapi.amap.com/v3/distance?';
  WeatherInfoURL := 'https://restapi.amap.com/v3/weather/weatherInfo?';
  GeofenceMetaURL := 'https://restapi.amap.com/v4/geofence/meta?';
  GeofenceStatusURL := 'https://restapi.amap.com/v4/geofence/status?';
end;

function TDMAMapWebAPI.Distance(const BeginLng, BeginLat, EndLng, EndLat, AType: string): string;
var
  URL, origin, destination: string;
begin
  { AType
    0：直线距离
    1：驾车导航距离（仅支持国内坐标）
    必须指出，当为1时会考虑路况，故在不同时间请求返回结果可能不同。
    此策略和驾车路径规划接口的 strategy=4策略基本一致，策略为“ 躲避拥堵的路线，但是可能会存在绕路的情况，耗时可能较长 ”
    若需要实现高德地图客户端效果，可以考虑使用驾车路径规划接口
    2：公交规划距离（仅支持同城坐标,QPS不可超过1，否则可能导致意外）
    3：步行规划距离
  }
  // 回返距离 m, FDMemTable切换到 results
  ClearStatus;
  URL := Concat(DistanceURL, 'key=', WebApiKey, A38);
  origin := Concat('origins=', BeginLng, A44, BeginLat, A38);
  destination := Concat('destination=', EndLng, A44, EndLat, A38); // results
  URL := Concat(URL, origin, destination, 'type=', AType);

  RESTClient.BaseURL := URL;
  RESTRequest.Method := TRESTRequestMethod.rmGET;
  RESTRequest.Execute;

  if (FDMemTable.FieldByName('status').AsInteger = 1) then
  begin
    RESTResponse.RootElement := 'results';
    Exit(FDMemTable.FieldByName('distance').AsString);
  end
  else
  begin
    Exit(FDMemTable.FieldByName('info').AsString);
  end;
end;

end.
