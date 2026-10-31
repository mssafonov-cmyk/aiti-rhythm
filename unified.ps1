# One desktop dashboard. Shared collector and physical cube stay unchanged.
$script:showCompleted=$true
$script:signalKey=''
$script:showDetails=$false
$script:cardSignals=@{}
function WeeklyRemaining($provider){
 if($provider -eq 'Codex'){
  if((Fresh $data.limits) -and $null -ne $data.limits.weekly_pct){return [Math]::Max(0.0,[Math]::Min(100.0,100*(1-[double]$data.limits.weekly_pct)))}
 }elseif((Fresh $data.claude) -and $data.claude.limits_at -and (NowSeconds)-$data.claude.limits_at -lt 600 -and $null -ne $data.claude.limits.seven_day.used_percentage){
  return [Math]::Max(0.0,[Math]::Min(100.0,100-[double]$data.claude.limits.seven_day.used_percentage))
 }
 return $null
}
function ViewOption($name){
 if($null -ne $data.view.$name){return [bool]$data.view.$name};return $true
}
function FiveHourRemaining($provider){
 if($provider -eq 'Codex'){
  if((Fresh $data.limits) -and $null -ne $data.limits.session_pct){return [Math]::Max(0,[Math]::Min(100,100*(1-[double]$data.limits.session_pct)))}
 }elseif((Fresh $data.claude) -and $data.claude.limits_at -and (NowSeconds)-$data.claude.limits_at -lt 600 -and $null -ne $data.claude.limits.five_hour.used_percentage){
  return [Math]::Max(0,[Math]::Min(100,100-[double]$data.claude.limits.five_hour.used_percentage))
 };return $null
}
function QuotaReset($provider,$window){
 try{
  if($provider -eq 'Codex'){$stamp=if($window -eq 'weekly'){$data.limits.weekly_reset_at}else{$data.limits.session_reset_at};if($stamp){return [DateTimeOffset]::FromUnixTimeSeconds([long]$stamp).ToLocalTime()}}
  else{$stamp=if($window -eq 'weekly'){$data.claude.limits.seven_day.resets_at}else{$data.claude.limits.five_hour.resets_at};if($stamp){return EventTime $stamp}}
 }catch{};return $null
}
function HasFiveHour{
 foreach($provider in @('Codex','Claude')){if($null -ne (FiveHourRemaining $provider)){return $true}};return $false
}
function QuotaHeight($narrow){return 71+$(if($narrow){24}else{0})+$(if(HasFiveHour){8}else{0})}
function DrawQuota($c,$narrow){
 $w=$c.Width;CardHeading $c 'ОСТАТОК НЕДЕЛИ' ''
 $gap=if($narrow){16}else{24};$half=($w-$gap)/2;$shift=if($narrow){24}else{0}
 $footer=58+$shift+$(if(HasFiveHour){8}else{0})
 for($i=0;$i -lt 2;$i++){
  $provider=@('Codex','Claude')[$i];$left=WeeklyRemaining $provider;$short=FiveHourRemaining $provider;$x=$i*($half+$gap)
  Put $c (Label $provider 11 '#939DA7') $x 24
  $value=Label $(if($null -eq $left){'—'}else{'{0:0.#}%' -f $left}) 22 $(if($null -ne $left -and $left -le 15){'#E6B66B'}else{'#E5E8EB'})
  $value.Name=$provider+'Remaining';$value.FontFamily='Bahnschrift';$value.Width=if($narrow){$half}else{$half-43};$value.TextAlignment=if($narrow){'Left'}else{'Right'}
  $value.ToolTip=if($null -eq $left){'Недельная квота недоступна в выбранном источнике.'}else{'Остаток недельной квоты '+$provider}
  Put $c $value $(if($narrow){$x}else{$x+43}) $(if($narrow){40}else{18})
  $week=[Windows.Controls.ProgressBar]::new();$week.Name=$provider+'WeekBar';$week.Width=$half;$week.Height=3;$week.Maximum=100;$week.Value=if($null -eq $left){0}else{$left};$week.Foreground=Brush '#A8BECD';$week.Background=Brush '#343D47';$week.BorderThickness=0;$week.Opacity=if($null -eq $left){0.35}else{1};$week.ToolTip=$value.ToolTip;Put $c $week $x (50+$shift)
  if($null -ne $short){
   $bar=[Windows.Controls.ProgressBar]::new();$bar.Name=$provider+'FiveHour';$bar.Width=$half;$bar.Height=2;$bar.Maximum=100;$bar.Value=$short;$bar.Foreground=Brush $(if($short -le 15){'#E6B66B'}else{'#99ADA9'});$bar.Background=Brush $(if($short -eq 0){'#6A5030'}else{'#343D47'});$bar.BorderThickness=0
   $shortReset=QuotaReset $provider 'session';$bar.ToolTip=('5 часов · остаток {0:0.#}%' -f $short)+$(if($shortReset){' · сброс '+$shortReset.ToString('dd.MM HH:mm')}else{' · дата сброса не передана'})
   [Windows.Automation.AutomationProperties]::SetName($bar,('Пятичасовой лимит '+$provider));Put $c $bar $x (57+$shift)
  }
  $reset=QuotaReset $provider 'weekly'
  $text=if($null -eq $left){'Квота недоступна'}elseif($reset){'До '+$reset.ToString('dd.MM HH:mm')}else{'Дата не передана'}
  $label=Label $text 9 '#939DA7';$label.Name=$provider+'Reset';$label.Width=$half;$label.ToolTip=if($reset){'Сброс недельной квоты: '+$reset.ToString('dd.MM.yyyy HH:mm')}else{'Источник передал расход, но не передал дату сброса недельной квоты.'};Put $c $label $x $footer
 }
}
function UsageData{
 if($data.usage){return $data.usage}
 $providers=@();foreach($entry in @(@('codex','Codex','C','#56D8F1'),@('claude','Claude','Cl','#BAABFF'))){
  $source=$data.($entry[0]);$known=(Fresh $source 180) -and $source.tokens
  $providers+=[pscustomobject]@{name=$entry[1];short=$entry[2];color=$entry[3];day_tokens=$(if($known){$source.tokens.input+$source.tokens.output}else{$null});per_min=$source.burn.per_min;series=$source.burn.series;note='Объём токенов, не денежная стоимость'}
 }
 return [pscustomobject]@{burn=$data.codex.burn;observed=$data.codex.observed;checked_at=$data.codex.checked_at;providers=$providers}
}
function ProviderColor($name){switch($name){'Claude'{return '#BAABFF'}'Antigravity'{return '#99DDAA'}default{return '#56D8F1'}}}
function TokenAmount($n){
 if($n -ge 1e6){return ('{0:0.#} млн' -f ($n/1e6))};if($n -ge 1e3){return ('{0:0.#} тыс' -f ($n/1e3))};return ('{0:0}' -f $n)
}
function UsageHeight($compact,$hot){return 60+$(if(-not $compact -or $showDetails){70}else{0})+$(if($showDetails -or ($hot -and -not $compact)){42}else{0})}
function DrawUsage($c,$y,$compact,$narrow){
 $w=$c.Width;$usage=UsageData;$burn=$usage.burn;$valid=(Fresh $usage 180) -and $usage.observed;$hot=$valid -and $burn.alert
 $minutes=if($burn.window_seconds){[int]($burn.window_seconds/60)}else{15}
 $heading=Label 'ТОКЕНЫ ЗА СЕГОДНЯ' 9 '#AAB7C4' $true;$heading.Name='DailyUsageHeading';$heading.Width=$w-30;$heading.ToolTip='С начала дня по МСК. Сумма по сессиям каждого инструмента, не стоимость подписки.';Put $c $heading 0 $y
 $providers=@($usage.providers);$cw=$w/[Math]::Max(1,$providers.Count)
 for($i=0;$i -lt $providers.Count;$i++){
  $p=$providers[$i];$x=$i*$cw
  $tip=$p.name+' · токены за сегодня: '+$(if($null -eq $p.day_tokens){'нет данных'}else{('{0:N0}' -f $p.day_tokens)})+"`n"+$(if($null -eq $p.per_min){'Скорость неизвестна'}else{(TokenAmount $p.per_min)+' ток/мин'})+"`n"+$p.note+$(if(-not @($p.series|Where-Object {$null -ne $_}).Count){"`nИстория графика недоступна"}else{''})
  if($p.cached_day){$tip+="`n* Последний сохранённый итог; источник пока не обновился.";if($p.day_updated_at){$tip+="`nОбновлено "+[DateTimeOffset]::FromUnixTimeSeconds([long]$p.day_updated_at).ToLocalTime().ToString('dd.MM HH:mm')}}
  $dot=[Windows.Shapes.Rectangle]::new();$dot.Width=3;$dot.Height=3;$dot.Fill=Brush $p.color;Put $c $dot $x ($y+21)
  $legend=Label $p.name 9 '#C4CED8';$legend.Name='Legend'+$p.name;$legend.Width=$cw-8;$legend.ToolTip=$tip;Put $c $legend ($x+7) ($y+16)
  $text=if($null -eq $p.day_tokens){'—'}else{$(if($p.partial){'от '}else{''})+(TokenAmount $p.day_tokens)}
  if($p.cached_day){$text+='*'}
  $value=Label $text $(if($text.Length -gt 9){11}else{13}) $(if($p.cached_day){'#ADB8C3'}else{'#E5E8EB'});$value.Name='Daily'+$p.name;$value.FontFamily='Bahnschrift';$value.Width=$cw-4;$value.ToolTip=$tip;Put $c $value $x ($y+29)
 }
 $speed=if($valid){$(if($usage.partial){'от '}else{''})+(TokenAmount $burn.per_min)+' ток/мин'}else{'нет данных'}
 $rate=Label ('Среднее за '+$minutes+' мин: '+$speed) 10 $(if($hot){'#E6B66B'}else{'#AAB7C4'});$rate.Name='TokenRate';$rate.Width=$w
 $rate.ToolTip='Средняя скорость по известным счётчикам за последние '+$minutes+' мин. Не расход за сутки.'+$(if($usage.partial){"`nПоказан минимум: у части источников неизвестна скорость."}else{''})+$(if($hot){"`n"+(BurnNoticeText $burn)}else{''});Put $c $rate 0 ($y+47)
 $more=FlatButton $(if($showDetails){'⌃'}else{'›'}) 25 {$script:showDetails=-not $showDetails;Draw};$more.Name='DetailsToggle';$more.Height=19;$more.ToolTip='График скорости и самая затратная сессия';Put $c $more ($w-25) ($y-3)
 if(-not $compact -or $showDetails){
  Divider $c ($y+64)
  $caption=Label 'Скорость за день' 9 '#AAB7C4';$caption.Width=$w*0.55;Put $c $caption 0 ($y+70)
  $allBars=@($providers|ForEach-Object {$_.series});$peak=($allBars|Measure-Object per_min -Maximum).Maximum
  $scale=Label $(if($null -ne $peak){'до '+(TokenAmount $peak)+'/мин'}else{'нет истории'}) 9 '#AAB7C4';$scale.Width=$w*0.45;$scale.TextAlignment='Right';Put $c $scale ($w*0.55) ($y+70)
  $count=($providers|ForEach-Object {@($_.series).Count}|Measure-Object -Maximum).Maximum
  foreach($p in $providers){$bars=@($p.series|Where-Object {$null -ne $_});if(-not $bars.Count){continue}
   $spark=[Windows.Shapes.Polyline]::new();$spark.Name='Graph'+$p.name;$spark.ToolTip=$p.name+' · ток/мин · интервалы 15 мин · общая шкала';$spark.Stroke=Brush $p.color;$spark.StrokeThickness=1.2
   for($j=0;$j -lt $bars.Count;$j++){$v=if($peak -gt 0){26*$bars[$j].per_min/$peak}else{0};[void]$spark.Points.Add([Windows.Point]::new(($w-2)*$j/[Math]::Max(1,$count-1),26-$v))};Put $c $spark 0 ($y+87)
  }
  $dates=@($allBars|Where-Object {$null -ne $_.at}|Sort-Object at)
  if($dates.Count){foreach($end in @(0,1)){$stamp=if($end){$dates[-1].at}else{$dates[0].at};$label=Label ([DateTimeOffset]::FromUnixTimeSeconds([long]$stamp).ToOffset([TimeSpan]::FromHours(3)).ToString('HH:mm')) 8 '#939DA7';$label.Width=$w/2;$label.TextAlignment=if($end){'Right'}else{'Left'};Put $c $label ($end*$w/2) ($y+115)}}
 }
 if($showDetails -or ($hot -and -not $compact)){
  $start=$y+130;$label=Label $(if($hot){'↑ Расход выше обычного'}else{'Сессия с наибольшим расходом'}) 9 $(if($hot){'#E6B66B'}else{'#AAB7C4'});$label.Width=$w;Put $c $label 0 ($start+2)
  $leaders=@($burn.leaders|Select-Object -First 1)
  if($valid -and $leaders.Count){$lead=$leaders[0];$row=FlatButton '' $w {param($s,$e) OpenSession $s.Tag};$row.Name='TokenLeader';$row.Tag=$lead.id;$row.ToolTip=$lead.provider+' · '+$lead.title;$row.IsEnabled=(-not $lead.provider -or $lead.provider -eq 'Codex');$row.Height=21;$label=Label ($(if($lead.provider){$lead.provider+' · '}else{''})+$lead.title) 10 '#BFB7A8';$label.Width=$w;$row.Content=$label;Put $c $row 0 ($start+17)}else{$empty=Label 'Пока не определена' 10 '#939DA7';$empty.Width=$w;Put $c $empty 0 ($start+17)}
 }
}

function ShowTodayMenu($sender){
 $popup=[Windows.Controls.ContextMenu]::new();$today=[DateTimeOffset]::Now.Date
 foreach($ev in @($data.calendar.events|Where-Object {(EventTime $_.planned_date).Date -eq $today})){
  $item=[Windows.Controls.MenuItem]::new();$item.Header=(EventTime $ev.planned_date).ToString('HH:mm')+' · '+$ev.subject;$item.Tag=$ev.ref
  $item.Add_Click({param($s,$e) $script:selectedRef=$s.Tag;Draw});[void]$popup.Items.Add($item)
 }
 if(-not $popup.Items.Count){$item=[Windows.Controls.MenuItem]::new();$item.Header='На сегодня встреч нет';$item.IsEnabled=$false;[void]$popup.Items.Add($item)}
 $popup.PlacementTarget=$sender;$popup.IsOpen=$true
}

function Card($rootCanvas,$name,$y,$height){
 $border=[Windows.Controls.Border]::new();$border.Name=$name;$border.Width=$rootCanvas.Width;$border.Height=$height;$border.CornerRadius=11;$border.BorderThickness=1;$border.BorderBrush=Brush '#323A43';$border.Background=Brush ('#{0:X2}1C232C' -f $bgAlpha);$border.Padding='14,12'
 $inside=[Windows.Controls.Canvas]::new();$inside.Width=$rootCanvas.Width-30;$inside.Height=$height-26;$inside.ClipToBounds=$true;$border.Child=$inside;Put $rootCanvas $border 0 $y
 return @{border=$border;canvas=$inside}
}
function Divider($c,$y){$line=[Windows.Shapes.Rectangle]::new();$line.Width=$c.Width;$line.Height=1;$line.Fill=Brush '#323A43';Put $c $line 0 $y}
function CardHeading($c,$title,$right=''){
 $heading=Label $title 10 '#939DA7' $true;$heading.Width=if($right){$c.Width*0.4}else{$c.Width-68};$heading.ToolTip=$title;Put $c $heading 0 0
 if($right){$t=Label $right 10 '#939DA7';$t.Width=$c.Width*0.6;$t.ToolTip=$right;$t.TextAlignment='Right';Put $c $t ($c.Width*0.4) 0}
}
function FlatButton($text,$width,$handler){$b=SmallButton $text $width $handler;$b.Background=Brush 'Transparent';$b.Foreground=Brush '#939DA7';$b.Padding='0';return $b}
function CardSignal($border,$key){
 if(-not $border){return};$name=$border.Name;$previous=$script:cardSignals[$name]
 if(-not $previous -or $previous.key -ne $key){$previous=@{key=$key;at=[DateTimeOffset]::UtcNow};$script:cardSignals[$name]=$previous}
 $tag=$key+'|'+$previous.at.Ticks;if($border.Tag -eq $tag){return};$border.Tag=$tag
 $base=if($key){'#9D7D4F'}else{'#323A43'};$brush=[Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString($base));$border.BorderBrush=$brush
 $elapsed=([DateTimeOffset]::UtcNow-$previous.at).TotalSeconds
 if($key -and $elapsed -lt 6 -and [Windows.SystemParameters]::ClientAreaAnimation){
  $animation=[Windows.Media.Animation.ColorAnimation]::new([Windows.Media.ColorConverter]::ConvertFromString('#323A43'),[Windows.Media.ColorConverter]::ConvertFromString('#E6B66B'),[Windows.Duration]::new([TimeSpan]::FromSeconds(1)))
  $animation.AutoReverse=$true;$animation.RepeatBehavior=[Windows.Media.Animation.RepeatBehavior]::new(3);$animation.BeginTime=[TimeSpan]::FromSeconds(-$elapsed);$animation.FillBehavior='Stop';$brush.BeginAnimation([Windows.Media.SolidColorBrush]::ColorProperty,$animation)
 }
}
function UpdateCardSignals{
 $event=SelectedEvent;$delta=if($event){(EventTime $event.planned_date).ToUnixTimeSeconds()-(NowSeconds)}else{999999}
 $meetingKey=if((CalendarFresh) -and $delta -gt 0 -and $delta -le 300){'meeting:'+$event.ref}else{''}
 $low=@();if(ViewOption 'limits'){foreach($provider in @('Codex','Claude')){$left=WeeklyRemaining $provider;if($null -ne $left -and $left -le 5){$low+=$provider};$short=FiveHourRemaining $provider;if($null -ne $short -and $short -le 5){$low+=($provider+'5h')}}}
 $usage=UsageData;$burnKey=if((ViewOption 'usage') -and (Fresh $usage 180) -and $usage.burn.alert){'burn:'+(@($usage.burn.leaders)[0].id)}else{''}
 CardSignal $script:meetingBorder $meetingKey;CardSignal $script:resourceBorder ($burnKey+($low -join ','))
 if($script:meetingBorder){
  $red=(CalendarFresh) -and $event -and -not $event.all_day -and $delta -le 60 -and $delta -ge -60
  # Keep the reminder visible throughout the entire five-minute window.
  # Wall-clock phase survives redraws and works when Windows animations are disabled.
  $bright=$meetingKey -and ([int][Math]::Floor((NowSeconds)/1.2)%2 -eq 0)
  $background=if($red){'50232B'}elseif($bright){'79521D'}else{'1C232C'}
  $alpha=if($bright){[Math]::Max(220,$bgAlpha)}else{$bgAlpha}
  $script:meetingBorder.Background=Brush ('#{0:X2}{1}' -f $alpha,$background)
  $script:meetingBorder.BorderThickness=if($meetingKey){3}else{1}
  $script:meetingBorder.BorderBrush=Brush $(if($red){'#F06A76'}elseif($bright){'#FFD34D'}elseif($meetingKey){'#9D7D4F'}else{'#323A43'})
 }
}
function CollectorStale{
 $timestamps=@($data.checked_at,$data.codex.checked_at,$data.calendar.checked_at,$data.limits.checked_at,$data.claude.checked_at,$data.antigravity.checked_at)|Where-Object {$_}
 $last=($timestamps|Measure-Object -Maximum).Maximum
 return (-not $last -or (NowSeconds)-$last -gt 180)
}
function RecoverCollector{
 if($SelfTest){$script:testRecovery=$true;return}
 try{
  $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$env:RHYTHM_CORE_EXE;$start.Arguments=$env:RHYTHM_CORE_PREFIX+' --recover';$start.UseShellExecute=$false;$start.CreateNoWindow=$true;[void][Diagnostics.Process]::Start($start)
  $script:notice='Обновление перезапускается'
 }catch{$script:notice='Не удалось перезапустить обновление'}
 $script:noticeAt=Get-Date;Draw
}
function CalendarVisible{
 if(-not (ViewOption 'calendar')){return $false};if($null -ne $data.calendar.enabled){return [bool]$data.calendar.enabled};return $true
}
function DrawUnified{
 $offset=if($script:sessionScroll){$script:sessionScroll.VerticalOffset}else{0}
 $Body.Children.Clear();$rootCanvas=[Windows.Controls.Canvas]::new();$rootCanvas.Width=[Math]::Max(230,$Body.ActualWidth);$rootCanvas.Height=[Math]::Max(0,$Body.ActualHeight);$rootCanvas.ClipToBounds=$true
 $view=[Windows.Controls.Border]::new();$outer=[Windows.Controls.ScrollViewer]::new();$outer.VerticalScrollBarVisibility='Hidden';$outer.HorizontalScrollBarVisibility='Disabled';$outer.Content=$rootCanvas;$view.Child=$outer;[void]$Body.Children.Add($view)
 $stale=CollectorStale;$bannerHeight=0
 $h=$rootCanvas.Height-$bannerHeight;$ev=SelectedEvent;$nearest=NextEvent;$usage=UsageData;$burn=$usage.burn;$valid=(Fresh $usage 180) -and $usage.observed;$hot=$valid -and $burn.alert
 $calendarVisible=CalendarVisible;$sessionsVisible=ViewOption 'sessions';$limitsVisible=ViewOption 'limits';$usageVisible=ViewOption 'usage';$compactUsage=ViewOption 'compact_usage';$automatic=ViewOption 'auto_height'
 $narrow=$rootCanvas.Width -lt 300;$meetingHeight=if($calendarVisible){130}else{0}
 $quotaHeight=if($limitsVisible){QuotaHeight $narrow}else{0}
 $usageHeight=if($usageVisible){UsageHeight $compactUsage $hot}else{0}
 $resourceHeight=if($limitsVisible -or $usageVisible){26+$quotaHeight+$usageHeight+$(if($limitsVisible -and $usageVisible){10}else{0})}else{0}
 $rows=@();foreach($source in @($data.codex,$data.claude,$data.antigravity)){if(Fresh $source 180){$rows+=@($source.sessions|Where-Object {$null -ne $_ -and ($showCompleted -or $_.status -ne 'idle')})}}
 $naturalSessions=if($sessionsVisible){$(if($automatic){50+31*[Math]::Min(4,[Math]::Max(1,$rows.Count))}else{134})}else{0}
 $cards=([int]$calendarVisible)+([int]$sessionsVisible)+([int]($resourceHeight -gt 0));$cardGaps=[Math]::Max(0,($cards-1)*10)
 $minimum=$meetingHeight+$naturalSessions+$resourceHeight+$cardGaps
 if($automatic){
  $h=$minimum;$desired=[Math]::Min($win.MaxHeight,[Math]::Min([Windows.SystemParameters]::WorkArea.Height-24,[Math]::Max(80,$h+56+$(if($notice){14}else{0}))))
  if([Math]::Abs($win.Height-$desired) -gt 1){$win.Height=$desired}
 }else{$h=[Math]::Max($rootCanvas.Height,$minimum)}
 $rootCanvas.Height=$h;$sessionHeight=if($sessionsVisible){$naturalSessions+$(if($automatic){0}else{[Math]::Max(0,$h-$minimum)})}else{0}
 $meetingGap=if($calendarVisible -and ($sessionsVisible -or $resourceHeight -gt 0)){10}else{0}
 $extra=1
 $script:meetingBorder=$null
 if($calendarVisible){
 $meeting=Card $rootCanvas 'MeetingCard' $bannerHeight $meetingHeight;$c=$meeting.canvas;$w=$c.Width;$script:meetingBorder=$meeting.border
 $dateCaption=if($ev){(EventTime $ev.planned_date).ToString('dd MMM',[Globalization.CultureInfo]::GetCultureInfo('ru-RU'))}else{''}
 CardHeading $c $(if($selectedRef){'ВЫБРАННАЯ ВСТРЕЧА'}else{'БЛИЖАЙШАЯ ВСТРЕЧА'}) ''
 $dateWidth=if($narrow){62}else{78};$today=FlatButton ($dateCaption+' ≡') $dateWidth {param($s,$e) ShowTodayMenu $s};$today.Name='TodayMeetings';$today.ToolTip='Встречи сегодня · '+$data.calendar.source+' · '+$data.calendar.account;$today.Height=19;Put $c $today ($w-$dateWidth) -3
 if($ev){
  $dt=EventTime $ev.planned_date;$delta=$dt.ToUnixTimeSeconds()-(NowSeconds)
  $urgentEvent=(CalendarFresh) -and $delta -gt 0 -and $delta -le 300;$accent=if($urgentEvent){'#E6B66B'}else{'#E5E8EB'}
  $time=Label $(if($ev.all_day){'Весь день'}else{$dt.ToString('HH:mm')}) $(if($ev.all_day){13}else{25}) $accent;$time.FontFamily='Bahnschrift';Put $c $time 0 20
  $title=Label ($ev.subject -replace '_',' ') 12 '#E5E8EB' $true;$title.TextWrapping='Wrap';$title.Width=$w-75;$title.Height=34;$title.ToolTip=$ev.subject;Put $c $title 75 21
  $until=if(-not (CalendarFresh)){'Календарь устарел'}elseif($delta -le 0){'Встреча началась'}elseif($delta -lt 3600){'Через '+[Math]::Ceiling($delta/60)+' мин'}elseif($delta -lt 86400){'Через '+[Math]::Floor($delta/3600)+' ч '+[Math]::Floor(($delta%3600)/60)+' мин'}else{'Через '+[Math]::Floor($delta/86400)+' д '+[Math]::Floor(($delta%86400)/3600)+' ч'}
  $caption=Label $until 11 $(if($urgentEvent){'#E6B66B'}else{'#939DA7'});$caption.Width=$w-114;$caption.ToolTip=$until;Put $c $caption 0 59
  $link=MeetingUrl $ev.telemost_url;$open=SmallButton 'Войти ↗' 76 {param($s,$e) MeetingAction $s.Tag};$open.Name='OpenMeeting';$open.Tag=$link;$open.IsEnabled=[bool]$link;$open.Background=Brush '#344251';$open.Foreground=Brush '#E5E8EB';$open.ToolTip=if($link){$link}else{'В источнике нет ссылки на встречу'}
  if($urgentEvent){$open.Background=Brush '#D7AF73';$open.Foreground=Brush '#1A2027'};Put $c $open ($w-110) 55
  $copy=FlatButton ([string][char]0xE8C8) 27 {param($s,$e) MeetingAction $s.Tag $true};$copy.Name='CopyMeeting';$copy.FontFamily='Segoe MDL2 Assets';$copy.Tag=$link;$copy.IsEnabled=[bool]$link;$copy.ToolTip='Скопировать ссылку';Put $c $copy ($w-27) 55
 }else{$empty=Label $(if(CalendarFresh){'Ближайших встреч нет'}else{'Нет свежих данных календаря'}) 13 '#939DA7';$empty.Width=$w;$empty.ToolTip=$empty.Text;Put $c $empty 0 35}
 Divider $c 84
 $future=@();$found=$false;foreach($event in @($data.calendar.events|Sort-Object {(EventTime $_.planned_date).ToUnixTimeSeconds()})){if($ev -and $event.ref -eq $ev.ref){$found=$true;continue};if($found){$future+=$event}}
 $y=87
 if($selectedRef){$back=FlatButton '‹ Ближайшая' 85 {$script:selectedRef='';Draw};$back.Name='NearestMeeting';Put $c $back 0 $y}
 foreach($event in @($future|Select-Object -First $extra)){
  $date=EventTime $event.planned_date;$stamp=if($ev -and $date.Date -eq $dt.Date){$date.ToString('HH:mm')}else{$date.ToString('dd.MM HH:mm')};$x=if($selectedRef -and $y -eq 87){93}else{0}
  $row=FlatButton '' ($w-$x) {param($s,$e) $script:selectedRef=$s.Tag;Draw};$row.Name='UpcomingMeeting';$row.Tag=$event.ref;$row.ToolTip=$event.subject;$row.Height=22
  $text=Label ('Далее · '+$stamp+' · '+($event.subject -replace '_',' ')) 10 '#939DA7';$text.Width=$w-$x;$row.Content=$text;Put $c $row $x $y;$y+=24
 }
 if(-not $future.Count -and -not $selectedRef){Put $c (Label 'Следующих встреч нет' 10 '#939DA7') 0 89}
 }
 $script:sessionScroll=$null
 if($sessionsVisible){
 $sessions=Card $rootCanvas 'SessionsCard' ($bannerHeight+$meetingHeight+$meetingGap) $sessionHeight;$c=$sessions.canvas;$w=$c.Width
 $all=@();foreach($source in @($data.codex,$data.claude,$data.antigravity)){if(Fresh $source 180){$all+=@($source.sessions)}}
 $active=@($all|Where-Object status -ne 'idle'|Sort-Object @{Expression={if($_.status -eq 'waiting'){0}elseif($_.status -eq 'working'){1}else{2}}},@{Expression='at';Descending=$true});$completed=@($all|Where-Object status -eq 'idle'|Sort-Object at -Descending)
 $waiting=@($active|Where-Object status -eq 'waiting').Count;$working=@($active|Where-Object status -eq 'working').Count
 CardHeading $c 'СЕССИИ' ([string]$waiting+' ждёт вас · '+$working+' работает')
 $scroll=[Windows.Controls.ScrollViewer]::new();$scroll.Name='SessionList';$scroll.Width=$w;$scroll.Height=[Math]::Max(28,$c.Height-24);$scroll.VerticalScrollBarVisibility='Hidden';$scroll.HorizontalScrollBarVisibility='Disabled';$stack=[Windows.Controls.StackPanel]::new();$scroll.Content=$stack;Put $c $scroll 0 24;$script:sessionScroll=$scroll
 $display=@($active);if($showCompleted){$display+=@($completed)}
 foreach($session in $display){
  $row=FlatButton '' $w {param($s,$e) OpenSession $s.Tag};$row.Name='SessionRow';$row.Tag=$session.id;$row.Height=31;$row.Padding='0'
  $grid=[Windows.Controls.Grid]::new();$grid.Width=$w;$left=[Windows.Controls.ColumnDefinition]::new();$right=[Windows.Controls.ColumnDefinition]::new();$right.Width=[Windows.GridLength]::new(88);[void]$grid.ColumnDefinitions.Add($left);[void]$grid.ColumnDefinitions.Add($right)
  $line=[Windows.Controls.StackPanel]::new();$line.Orientation='Horizontal';$line.VerticalAlignment='Center';[void]$line.Children.Add((StatusGlyph $session.status));$name=if($session.title){$session.title}else{$session.project};$badge=Label $(switch($session.provider){'Antigravity'{'A'}'Claude'{'Cl'}default{'C'}}) 9 (ProviderColor $session.provider);$badge.Width=19;[void]$line.Children.Add($badge);$title=Label $name 11 '#E5E8EB';$title.Width=[Math]::Max(25,$w-129);[void]$line.Children.Add($title);[void]$grid.Children.Add($line)
  $status=switch($session.status){'waiting'{'ждёт вас'}'working'{'работает'}'idle'{'завершена'}default{'неизвестно'}};$color=switch($session.status){'waiting'{'#76B6EF'}'working'{'#99ADA9'}'idle'{'#E6B66B'}default{'#939DA7'}}
  if($session.rate.level -in @('warning','critical')){$status='↑ расход ×'+$session.rate.ratio;$color='#E6B66B'}
  $state=Label $status 10 $color;$state.VerticalAlignment='Center';$state.TextAlignment='Right';[Windows.Controls.Grid]::SetColumn($state,1);[void]$grid.Children.Add($state);$row.Content=$grid;$row.ToolTip=$session.provider+' · '+$name
  $row.IsEnabled=$session.provider -eq 'Codex' -and $session.id -match '^[0-9a-f-]{36}$';[void]$stack.Children.Add($row)
 }
 if(-not $display.Count){[void]$stack.Children.Add((Label $(if($stale){'Список сессий устарел'}else{'Нет активных сессий'}) 12 '#939DA7'))};$scroll.ScrollToVerticalOffset($offset)
 }
 $script:resourceBorder=$null
 if($resourceHeight -gt 0){
  $resourceY=$meetingHeight+$meetingGap+$sessionHeight+$(if($sessionsVisible){10}else{0})
  $resource=Card $rootCanvas 'ResourcesCard' $resourceY $resourceHeight;$c=$resource.canvas;$script:resourceBorder=$resource.border
  if($limitsVisible){DrawQuota $c $narrow}
  if($usageVisible){$usageY=if($limitsVisible){$quotaHeight+10}else{0};if($limitsVisible){Divider $c ($quotaHeight+3)};DrawUsage $c $usageY $compactUsage $narrow}
 }
 UpdateFreshnessIndicator
 $Foot.Text=$notice;$Foot.Visibility=if($notice){'Visible'}else{'Collapsed'}
 UpdateCardSignals
}

function UpdateFreshnessIndicator{
 $stale=CollectorStale
 $problem=if($stale){'Нет обновлений'}elseif($data.codex.enabled -ne $false -and -not (Fresh $data.codex 180)){'Codex устарел'}elseif($data.claude.enabled -ne $false -and -not (Fresh $data.claude 180)){'Claude устарел'}elseif((CalendarVisible) -and -not (CalendarFresh)){'Календарь устарел'}elseif($data.cube.enabled -and $data.cube.error){'Кубик недоступен'}else{''}
 $LiveDot.Text=if($problem){' · '+$problem}else{''}
 $LiveDot.Foreground=Brush '#F06A76'
 $LiveDot.ToolTip=if($problem){$problem+' · МСК. Восстановление сборщика — в настройках.'}else{$null}
}
