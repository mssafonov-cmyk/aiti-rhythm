param([switch]$SelfTest,[switch]$LifecycleTest,[string]$DataRoot)
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition 'public static class WidgetConsole { [System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow(); }'
$script:hasConsole=[WidgetConsole]::GetConsoleWindow() -ne [IntPtr]::Zero
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms,System.Drawing
$script:assetRoot=$PSScriptRoot
$script:root=if($DataRoot){$DataRoot}else{Join-Path $env:LOCALAPPDATA 'AITI/Rhythm/data'}
[void][IO.Directory]::CreateDirectory($root)
$script:statePath=Join-Path $root 'widget-state.json'
$script:statusPath=Join-Path $root 'widget-status.json'
$script:logPath=Join-Path $root 'widget.log'
$created=$false
$mutex=New-Object Threading.Mutex($true,'Local\AITI-Rhythm-Personal-Widget',([ref]$created))
if(-not $created -and -not $SelfTest){[IO.File]::WriteAllText((Join-Path $root 'widget-show.signal'),'show');exit}
$script:page=0; $script:auto=$true; $script:locked=$false; $script:bgAlpha=255
$script:selectedRef='';$script:dayList=$false;$script:lastBurnNotice=0
$script:changed=Get-Date; $script:data=$null; $script:signature=''; $script:urgent=$false
$script:restorePage=0; $script:notice=''; $script:noticeAt=Get-Date; $script:closing=$false
$script:colors=@('#56D8F1','#99ADA9','#BAABFF','#FFD374')
[xml]$xaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
 Title="АйТи:Ритм" Width="380" Height="600" MinWidth="260" MinHeight="600" MaxWidth="600" MaxHeight="900"
 WindowStyle="None" AllowsTransparency="True" Background="Transparent" ResizeMode="CanResizeWithGrip" ShowInTaskbar="False" Topmost="True" FontFamily="Segoe UI" Foreground="#EDF4FD">
 <Window.Resources>
  <Style TargetType="Button"><Setter Property="Background" Value="Transparent"/><Setter Property="Foreground" Value="#94A7BF"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Padding" Value="5,3"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="B" CornerRadius="7" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="#25364A"/><Setter Property="Foreground" Value="White"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.55"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
 </Window.Resources>
 <Border x:Name="Shell" CornerRadius="19" BorderThickness="1" BorderBrush="#505963" Background="#FF151B22" Padding="14,9,14,8">
  <Grid><Grid.RowDefinitions><RowDefinition Height="29"/><RowDefinition Height="*"/><RowDefinition Height="0"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
   <Grid x:Name="DragBar" Background="Transparent" Cursor="SizeAll"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="0"/><ColumnDefinition Width="28"/><ColumnDefinition Width="28"/><ColumnDefinition Width="0"/></Grid.ColumnDefinitions>
    <StackPanel Orientation="Horizontal" VerticalAlignment="Center" ClipToBounds="True"><Image Width="16" Height="16" VerticalAlignment="Center" Source="{Binding Icon, RelativeSource={RelativeSource AncestorType=Window}}" Margin="0,0,7,0"/><TextBlock Text="АйТи:Ритм" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center" Foreground="#E5EDF7"/><TextBlock x:Name="LiveDot" Text="" FontSize="9" Foreground="#73E0B3" VerticalAlignment="Center"/></StackPanel>
    <Button Visibility="Collapsed" x:Name="Pin" Grid.Column="1" Content="◇" ToolTip="Закрепить положение"/>
    <Button x:Name="Options" Grid.Column="2" Content="⚙" FontSize="16" ToolTip="Настройки: прозрачность фона, скорость"/>
    <Button x:Name="Hide" Grid.Column="3" Content="−" ToolTip="Скрыть в трей"/>
    <Button Visibility="Collapsed" x:Name="Power" Grid.Column="4" Content="×" Foreground="#FFAD91" ToolTip="Скрыть в трей. Выключение — в настройках"/>
   </Grid>
   <Grid x:Name="Body" Grid.Row="1" Margin="0,3,0,5"/>
   <UniformGrid x:Name="Tabs" Grid.Row="2" Columns="4"/>
   <TextBlock x:Name="Foot" Grid.Row="3" FontSize="9" Foreground="#8194AD" VerticalAlignment="Bottom" TextTrimming="CharacterEllipsis"/>
  </Grid>
 </Border>
</Window>
'@
$script:win=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $xaml))
foreach($name in @('Shell','DragBar','LiveDot','Pin','Options','Hide','Power','Body','Tabs','Foot')){Set-Variable -Name $name -Value $win.FindName($name) -Scope Script}
function Brush($s){[Windows.Media.BrushConverter]::new().ConvertFromString($s)}
function Label($s,$size=12,$color='#EDF4FD',$bold=$false){
 $t=[Windows.Controls.TextBlock]::new();$t.Text=[string]$s;$t.FontSize=$size;$t.Foreground=Brush $color
 if($bold){$t.FontWeight='SemiBold'};$t.TextTrimming='CharacterEllipsis';return $t
}
function Put($panel,$item,$left,$top){[Windows.Controls.Canvas]::SetLeft($item,$left);[Windows.Controls.Canvas]::SetTop($item,$top);[void]$panel.Children.Add($item)}
function Num($n){if($n -ge 1e6){return ('{0:0.0}M' -f ($n/1e6))};if($n -ge 1e3){return ('{0:0.0}K' -f ($n/1e3))};return [string]$n}
function BurnNoticeText($burn){
 $summary='Сейчас '+(Num $burn.per_min)+' ток/мин.'
 $leader=@($burn.leaders|Select-Object -First 1)
 if(-not $leader.Count){return $summary+"`nСессию определить не удалось."}
 $item=$leader[0];$name=if($item.title){[string]$item.title}elseif($item.project){[string]$item.project}else{'Без названия'}
 $name=($name -replace '\s+',' ').Trim()
 if(-not $name){$name='Без названия'}
 if($name.Length -gt 90){$length=89;if([char]::IsHighSurrogate($name[$length-1])){$length--};$name=$name.Substring(0,$length)+'…'}
 $detail=if($burn.leader_basis -eq 'day'){'За день: '+(Num $item.day_tokens)+' токенов.'}elseif($null -ne $item.per_min){'Её расход: '+(Num $item.per_min)+' ток/мин.'}else{'Расход сессии недоступен.'}
 return $summary+"`nСессия Codex: "+$name+"`n"+$detail
}
function NowSeconds{[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()}
function Fresh($obj,$seconds=600){return ($null -ne $obj -and -not $obj.error -and $null -ne $obj.checked_at -and ((NowSeconds)-[double]$obj.checked_at) -lt $seconds)}
function EventTime($s){
 # Lake timestamps without offset are Moscow wall time, independently of PC timezone.
 if($s -notmatch '(Z|[+-]\d\d:\d\d)$'){$s+='+03:00'}
 return [DateTimeOffset]::Parse($s).ToLocalTime()
}
function CalendarFresh{
 try{return ((Fresh $data.calendar 180) -and ((NowSeconds)-(EventTime $data.calendar.synced_at).ToUnixTimeSeconds()) -lt 900)}catch{return $false}
}
function NextEvent{
 foreach($ev in $data.calendar.events){if($ev.all_day){continue};$end=(EventTime $ev.planned_date).ToUnixTimeSeconds()+300;if($end -ge (NowSeconds)){return $ev}};return $null
}
function SelectedEvent{
 if($selectedRef){$found=@($data.calendar.events|Where-Object ref -eq $selectedRef);if($found.Count){return $found[0]}}
 return NextEvent
}
function MoveMeeting($step){
 $events=@($data.calendar.events);if(-not $events.Count){return};$current=SelectedEvent;$idx=0
 for($i=0;$i -lt $events.Count;$i++){if($events[$i].ref -eq $current.ref){$idx=$i;break}}
 $idx=[Math]::Max(0,[Math]::Min($events.Count-1,$idx+$step));$script:selectedRef=$events[$idx].ref;$script:dayList=$false;$script:changed=Get-Date;Draw
}
function SmallButton($text,$width,$action){$b=[Windows.Controls.Button]::new();$b.Content=$text;$b.Width=$width;$b.Height=24;$b.FontSize=11;$b.Background=Brush '#263449';$b.Add_Click($action);return $b}
function StatusGlyph($state){
 $dot=[Windows.Shapes.Ellipse]::new();$dot.Width=9;$dot.Height=9;$dot.Margin='0,0,7,0';$dot.VerticalAlignment='Center'
 switch($state){
  'waiting'{$dot.Fill=Brush '#76B6EF'}
  'idle'{$dot.Fill=Brush '#E6B66B'}
  'working'{
   $dot.Stroke=Brush '#99ADA9';$dot.StrokeThickness=2;$dashes=[Windows.Media.DoubleCollection]::new();$dashes.Add(3.0);$dashes.Add(2.0);$dot.StrokeDashArray=$dashes
   $spin=[Windows.Media.RotateTransform]::new(0,4.5,4.5);$dot.RenderTransform=$spin
   $animation=[Windows.Media.Animation.DoubleAnimation]::new(0,360,[Windows.Duration]::new([TimeSpan]::FromSeconds(1.2)));$animation.RepeatBehavior=[Windows.Media.Animation.RepeatBehavior]::Forever
   $spin.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty,$animation)
  }
  default{$dot.Fill=Brush '#94A7BF'}
 };return $dot
}
function RateColor($level){switch($level){'critical'{'#FF7F87'}'warning'{'#FFD374'}'normal'{'#99ADA9'}'below'{'#76B6EF'}'idle'{'#94A7BF'}default{'#BAABFF'}}}
function SaveState{
 if($SelfTest){return}
 @{x=$win.Left;y=$win.Top;width=$win.Width;height=$win.Height;design=2;locked=$locked;topmost=$win.Topmost;auto=$auto;page=$page;alpha=$bgAlpha;showCompleted=$showCompleted}|ConvertTo-Json|Set-Content -LiteralPath $statePath -Encoding UTF8
}
function FitScreen{
 # WPF positions use DIPs; convert work areas from physical pixels.
 $source=[Windows.PresentationSource]::FromVisual($win);$sx=1.0;$sy=1.0
 if($source){$sx=$source.CompositionTarget.TransformToDevice.M11;$sy=$source.CompositionTarget.TransformToDevice.M22}
 $areas=@([Windows.Forms.Screen]::AllScreens | ForEach-Object { [Windows.Rect]::new($_.WorkingArea.X/$sx,$_.WorkingArea.Y/$sy,$_.WorkingArea.Width/$sx,$_.WorkingArea.Height/$sy) })
 $rect=[Windows.Rect]::new($win.Left,$win.Top,$win.Width,$win.Height)
 $target=$null
 foreach($a in $areas){$over=[Windows.Rect]::Intersect($rect,$a);if(-not $over.IsEmpty -and $over.Width -ge 80 -and $over.Height -ge 35){$target=$a;break}}
 if($null -eq $target){$target=$areas[-1];$win.Left=$target.Right-$win.Width-18;$win.Top=$target.Bottom-$win.Height-18}
 $win.Left=[Math]::Max($target.Left,[Math]::Min($win.Left,$target.Right-$win.Width));$win.Top=[Math]::Max($target.Top,[Math]::Min($win.Top,$target.Bottom-$win.Height))
}
function Ring($panel,$cx,$cy,$value,$color,$name){
 $r=39;$base=[Windows.Shapes.Ellipse]::new();$base.Width=78;$base.Height=78;$base.Stroke=Brush '#253449';$base.StrokeThickness=6;Put $panel $base ($cx-$r) ($cy-$r)
 if($null -ne $value -and $value -gt 0){
  $v=[Math]::Min(99.99,[Math]::Max(0,$value));$angle=$v/100*2*[Math]::PI
  $endX=$cx+$r*[Math]::Sin($angle);$endY=$cy-$r*[Math]::Cos($angle);$large=if($v -gt 50){1}else{0}
  $path=[Windows.Shapes.Path]::new();$path.Stroke=Brush $color;$path.StrokeThickness=6;$path.StrokeStartLineCap='Round';$path.StrokeEndLineCap='Round'
  $geometry=[string]::Format([Globalization.CultureInfo]::InvariantCulture,'M {0},{1} A 39,39 0 {2} 1 {3},{4}',$cx,($cy-$r),$large,$endX,$endY)
  $path.Data=[Windows.Media.Geometry]::Parse($geometry);[void]$panel.Children.Add($path)
 }
 $s=if($null -eq $value){'—'}else{'{0:0}%' -f $value};$t=Label $s 27 $color $true;$t.FontFamily='Bahnschrift';$t.Width=90;$t.TextAlignment='Center';Put $panel $t ($cx-45) ($cy-19)
 $t=Label $name 12 $color $true;$t.Width=130;$t.TextAlignment='Center';Put $panel $t ($cx-65) ($cy-66)
}
function SelectPage($n){$script:page=$n;$script:changed=Get-Date;Draw;SaveState}
function OpenSession($id){
 if($id -notmatch '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'){return}
 $url='codex://threads/'+$id
 if($SelfTest){$script:testSessionUrl=$url;return}
 try{Start-Process -FilePath $url; $script:notice='Открываю выбранный чат…';$script:noticeAt=Get-Date;Add-Content -LiteralPath $logPath -Value ((Get-Date -Format o)+' open '+$url)}catch{$script:notice='Не удалось открыть Codex';Add-Content -LiteralPath $logPath -Value $_.Exception.Message}
 $Foot.Text=$notice
}
function MeetingUrl($value){
 try{
  $u=[Uri]$value
  if(-not $u.IsAbsoluteUri -or $u.Scheme -ne 'https' -or $u.UserInfo -or -not $u.IsDefaultPort){return $null}
  if($u.DnsSafeHost -notin @('telemost.360.yandex.ru','telemost.yandex.ru','meet.google.com','zoom.us') -and -not $u.DnsSafeHost.EndsWith('.zoom.us')){return $null}
  if($u.DnsSafeHost -in @('telemost.360.yandex.ru','telemost.yandex.ru') -and $u.AbsolutePath -notmatch '^/j/[^/]+/?$'){return $null}
  if($u.DnsSafeHost -eq 'meet.google.com' -and $u.AbsolutePath -notmatch '^/[a-z]{3}-[a-z]{4}-[a-z]{3}/?$'){return $null}
  if(($u.DnsSafeHost -eq 'zoom.us' -or $u.DnsSafeHost.EndsWith('.zoom.us')) -and $u.AbsolutePath -notmatch '^/(j|my)/[^/]+/?$'){return $null}
  return $u.AbsoluteUri
 }catch{return $null}
}
function MeetingAction($value,$copy=$false){
 $url=MeetingUrl $value
 if(-not $url){$script:notice='У встречи нет корректной ссылки';$script:noticeAt=Get-Date;return}
 if($SelfTest){$script:testMeetingAction=@{url=$url;copy=$copy};return}
 try{
  if($copy){[Windows.Clipboard]::SetText($url);$script:notice='Ссылка на встречу скопирована'}
  else{Start-Process -FilePath $url;$script:notice='Открываю Телемост…'}
  Add-Content -LiteralPath $logPath -Value ((Get-Date -Format o)+' meeting-action copy='+$copy)
 }catch{$script:notice='Не удалось выполнить действие';Add-Content -LiteralPath $logPath -Value $_.Exception.Message}
 $script:noticeAt=Get-Date;$Foot.Text=$notice
}
. (Join-Path $assetRoot 'unified.ps1')
function Draw { DrawUnified }
$DragBar.Add_MouseLeftButtonDown({param($sender,$e) if(-not $locked -and $e.OriginalSource -isnot [Windows.Controls.Button]){try{$win.DragMove();FitScreen;SaveState}catch{}}})
$Pin.Add_Click({$script:locked=-not $locked;$Pin.Content=if($locked){'◆'}else{'◇'};$DragBar.Cursor=if($locked){'Arrow'}else{'SizeAll'};SaveState})
$Hide.Add_Click({$win.Hide()})
$Power.Add_Click({$win.Hide()})
$menu=[Windows.Controls.ContextMenu]::new()
function MenuItem($text,$handler){$m=[Windows.Controls.MenuItem]::new();$m.Header=$text;$m.Add_Click($handler);[void]$menu.Items.Add($m);return $m}
$script:auto=$false
$null=MenuItem ('О программе · '+$env:RHYTHM_VERSION) {[void][Windows.MessageBox]::Show(('АйТи:Ритм '+$env:RHYTHM_VERSION+"`nИсходники: "+$env:RHYTHM_BUILD_COMMIT),'АйТи:Ритм')}
$completedMenu=MenuItem 'Показывать завершённые сессии' {$script:showCompleted=$completedMenu.IsChecked;Draw;SaveState};$completedMenu.IsCheckable=$true;$completedMenu.IsChecked=$showCompleted
$null=MenuItem 'Подключения Codex, Claude, календаря и кубика…' {
 $dialog=Join-Path $assetRoot 'connections.ps1'
 $power=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
 Start-Process -FilePath $power -WindowStyle Hidden -ArgumentList @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',('"'+$dialog+'"'),'-DataRoot',('"'+$root+'"'))
}
$null=MenuItem 'Компактная ширина · 260' {$right=$win.Left+$win.Width;$win.Width=260;$win.Left=$right-$win.Width;FitScreen;Draw;SaveState}
$null=MenuItem 'Обычная ширина · 380' {$right=$win.Left+$win.Width;$win.Width=380;$win.Left=$right-$win.Width;FitScreen;Draw;SaveState}
$null=MenuItem 'Восстановить обновление данных' {RecoverCollector}
$lockMenu=MenuItem 'Закрепить положение' {$Pin.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))};$lockMenu.IsCheckable=$true
$topMenu=MenuItem 'Поверх окон' {$win.Topmost=$topMenu.IsChecked;SaveState};$topMenu.IsCheckable=$true;$topMenu.IsChecked=$true
$monitorMenu=MenuItem 'Перенести на другой монитор' {
 $screens=[Windows.Forms.Screen]::AllScreens;$src=[Windows.PresentationSource]::FromVisual($win);$scale=$src.CompositionTarget.TransformToDevice.M11
 $point=[System.Drawing.Point]::new([int](($win.Left+50)*$scale),[int](($win.Top+50)*$scale));$cur=[Windows.Forms.Screen]::FromPoint($point);$idx=0
 for($j=0;$j -lt $screens.Count;$j++){if($screens[$j].DeviceName -eq $cur.DeviceName){$idx=($j+1)%$screens.Count;break}}
 $area=$screens[$idx].WorkingArea;$win.Left=$area.Right/$scale-$win.Width-18;$win.Top=$area.Bottom/$scale-$win.Height-18;FitScreen;SaveState
}
$opacityMenu=[Windows.Controls.MenuItem]::new();$opacityMenu.Header='Прозрачность фона (по умолчанию 0%)';[void]$menu.Items.Add($opacityMenu)
foreach($option in @(@('Лёгкая · 15%',217),@('Средняя · 35%',166),@('Сильная · 50%',128),@('Непрозрачный',255))){$mi=[Windows.Controls.MenuItem]::new();$mi.Header=$option[0];$mi.Tag=$option[1];$mi.Add_Click({param($sender,$e) $script:bgAlpha=[int]$sender.Tag;$Shell.Background=Brush ('#{0:X2}151B22' -f $bgAlpha);Draw;SaveState});[void]$opacityMenu.Items.Add($mi)}
$rateMenu=[Windows.Controls.MenuItem]::new();$rateMenu.Header='Окно скорости токенов';[void]$menu.Items.Add($rateMenu)
foreach($minutes in @(15,30,60)){$mi=[Windows.Controls.MenuItem]::new();$mi.Header=[string]$minutes+' минут';$mi.Tag=$minutes;$mi.Add_Click({param($sender,$e) @{window_minutes=[int]$sender.Tag}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'metric-options.json') -Encoding UTF8;$script:notice='Окно изменится после обновления данных';$script:noticeAt=Get-Date;$Foot.Text=$notice});[void]$rateMenu.Items.Add($mi)}
$null=MenuItem 'Выключить приложение' {$script:closing=$true;$win.Close()}
$Options.Add_Click({$completedMenu.IsChecked=$showCompleted;$lockMenu.IsChecked=$locked;$opacityMenu.Header='Прозрачность фона: '+[Math]::Round(100*(255-$bgAlpha)/255)+'%';$rateMenu.Header='Окно скорости: '+$(if($data.codex.burn.window_seconds){[int]($data.codex.burn.window_seconds/60)}else{15})+' мин';$menu.PlacementTarget=$Options;$menu.IsOpen=$true})
$tray=[Windows.Forms.NotifyIcon]::new();$tray.Icon=[System.Drawing.Icon]::new((Join-Path $assetRoot 'indicators.ico'));$tray.Text='АйТи:Ритм';$tray.Visible=-not $SelfTest
$win.Icon=[Windows.Media.Imaging.BitmapFrame]::Create([Uri](Join-Path $assetRoot 'indicators.ico'))
$tray.Add_DoubleClick({$win.Show();FitScreen;[void]$win.Activate()})
$trayMenu=[Windows.Forms.ContextMenuStrip]::new();$null=$trayMenu.Items.Add('Показать');$trayMenu.Items[0].Add_Click({$win.Show();FitScreen;[void]$win.Activate()});$null=$trayMenu.Items.Add('Выключить АйТи:Ритм');$trayMenu.Items[1].Add_Click({$script:closing=$true;$win.Close()});$tray.ContextMenuStrip=$trayMenu
$win.Add_Closing({param($s,$e) if(-not $closing -and -not $SelfTest){$e.Cancel=$true;$win.Hide()}else{SaveState;$tray.Dispose()}})
$win.Add_SizeChanged({SaveState})
$Body.Add_SizeChanged({if($script:data -and -not $script:layoutBusy){$script:layoutBusy=$true;try{Draw}finally{$script:layoutBusy=$false}}})
try{
 if(Test-Path -LiteralPath $statePath){$s=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json;$win.Left=$s.x;$win.Top=$s.y;$win.Width=[Math]::Max(260,[Math]::Min(600,$s.width));$win.Height=[Math]::Max(600,[Math]::Min(900,$s.height));$script:locked=[bool]$s.locked;$win.Topmost=[bool]$s.topmost;$script:auto=[bool]$s.auto;$script:page=[Math]::Max(0,[Math]::Min(3,[int]$s.page));if($null -ne $s.showCompleted){$script:showCompleted=[bool]$s.showCompleted};if($s.alpha){$script:bgAlpha=[int]$s.alpha};if($s.design -ne 2){$win.Height=[Math]::Max(600,$win.Height)}}
 else{$win.Left=-10000;$win.Top=-10000}
}catch{$win.Left=-10000;$win.Top=-10000}
$script:auto=$false;$topMenu.IsChecked=$win.Topmost;$Pin.Content=if($locked){'◆'}else{'◇'};$Shell.Background=Brush ('#{0:X2}151B22' -f $bgAlpha)
function Tick{
 try{
  $stopSignal=Join-Path $root 'widget-stop.signal'
  if(-not $SelfTest -and (Test-Path -LiteralPath $stopSignal)){Remove-Item -LiteralPath $stopSignal;$script:closing=$true;$win.Close();return}
  $showSignal=Join-Path $root 'widget-show.signal'
  if(-not $SelfTest -and (Test-Path -LiteralPath $showSignal)){Remove-Item -LiteralPath $showSignal;$win.Show();FitScreen;[void]$win.Activate()}
  if($notice -and ((Get-Date)-$noticeAt).TotalSeconds -gt 5){$script:notice=''}
  $stream=[IO.FileStream]::new((Join-Path $root 'snapshot.json'),[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
  $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8)
  try{$script:data=$reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose()}
  $ev=NextEvent;$delta=if($ev){(EventTime $ev.planned_date).ToUnixTimeSeconds()-(NowSeconds)}else{999999}
  $urgentNow=(CalendarFresh) -and $delta -gt 0 -and $delta -le 300
  $script:urgent=$urgentNow
  $hot=(Fresh $data.codex 180) -and $data.codex.burn.alert
  UpdateCardSignals;UpdateFreshnessIndicator
  if($hot -and -not $SelfTest -and (NowSeconds)-$lastBurnNotice -gt 600){$tray.ShowBalloonTip(5000,'Расход токенов ускорился',(BurnNoticeText $data.codex.burn),[Windows.Forms.ToolTipIcon]::Warning);$script:lastBurnNotice=NowSeconds}
  # Freeze interactive controls under the pointer; explicit clicks redraw immediately.
  if($Body.Children.Count -eq 0 -or (-not $win.IsMouseOver -and [Windows.Input.Mouse]::LeftButton -ne 'Pressed')){Draw}
  FitScreen
  if(-not $SelfTest){@{pid=$PID;at=(NowSeconds);page=$page;urgent=$urgent;visible=$win.IsVisible;showInTaskbar=$win.ShowInTaskbar;trayVisible=$tray.Visible;hasConsole=$script:hasConsole;monitors=[Windows.Forms.Screen]::AllScreens.Count;source='snapshot.json';design=2;title=$win.Title}|ConvertTo-Json|Set-Content -LiteralPath $statusPath -Encoding UTF8}
 }catch{$LiveDot.Text=' · Ошибка данных';$LiveDot.Foreground=Brush '#F06A76';Add-Content -LiteralPath $logPath -Value ((Get-Date -Format o)+' '+$_.Exception.Message)}
}
$timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[TimeSpan]::FromSeconds(1);$timer.Add_Tick({Tick})
$win.Add_ContentRendered({FitScreen;Tick;SaveState})
if($SelfTest){
 . (Join-Path $assetRoot 'unified-test.ps1')
}else{
 # Hide ends ShowDialog's nested loop. Keep the dispatcher alive until explicit exit.
 $app=[Windows.Application]::new()
 $app.ShutdownMode=[Windows.ShutdownMode]::OnExplicitShutdown
 $win.Add_Closed({$app.Shutdown()})
 if($LifecycleTest){. (Join-Path $assetRoot 'widget-lifecycle-test.ps1')}
 $timer.Start()
 try{[void]$app.Run($win)}finally{$timer.Stop()}
 if($LifecycleTest -and $script:lifecycleFailure){throw $script:lifecycleFailure}
}
$tray.Dispose();if($created){$mutex.ReleaseMutex()};$mutex.Dispose()
