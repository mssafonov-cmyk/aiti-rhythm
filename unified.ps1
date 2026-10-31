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
 $low=@();foreach($provider in @('Codex','Claude')){$left=WeeklyRemaining $provider;if($null -ne $left -and $left -le 5){$low+=$provider}}
 $burnKey=if((Fresh $data.codex 180) -and $data.codex.burn.alert){'burn:'+(@($data.codex.burn.leaders)[0].id)}else{''}
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
 $timestamps=@($data.checked_at,$data.codex.checked_at,$data.calendar.checked_at,$data.limits.checked_at,$data.claude.checked_at)|Where-Object {$_}
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
 if($null -ne $data.calendar.enabled){return [bool]$data.calendar.enabled};return $true
}
function DrawUnified{
 $offset=if($script:sessionScroll){$script:sessionScroll.VerticalOffset}else{0}
 $Body.Children.Clear();$rootCanvas=[Windows.Controls.Canvas]::new();$rootCanvas.Width=[Math]::Max(230,$Body.ActualWidth);$rootCanvas.Height=[Math]::Max(470,$Body.ActualHeight);$rootCanvas.ClipToBounds=$true
 $view=[Windows.Controls.Border]::new();$outer=[Windows.Controls.ScrollViewer]::new();$outer.VerticalScrollBarVisibility='Hidden';$outer.HorizontalScrollBarVisibility='Disabled';$outer.Content=$rootCanvas;$view.Child=$outer;[void]$Body.Children.Add($view)
 $stale=CollectorStale;$bannerHeight=0
 $h=$rootCanvas.Height-$bannerHeight;$ev=SelectedEvent;$nearest=NextEvent;$burn=$data.codex.burn;$valid=(Fresh $data.codex 180) -and $data.codex.observed;$hot=$valid -and $burn.alert
 $calendarVisible=CalendarVisible;$meetingGap=if($calendarVisible){10}else{0};$cardGaps=10+$meetingGap;$extra=1;$meetingHeight=if($calendarVisible){130}else{0};$narrow=$rootCanvas.Width -lt 300;$resourceHeight=174+$(if($narrow){36}else{0})+$(if($hot -or $showDetails){80}else{0});$h=[Math]::Max($h,$meetingHeight+$resourceHeight+134);$rootCanvas.Height=$h+$bannerHeight;$sessionHeight=$h-$meetingHeight-$resourceHeight-$cardGaps
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
 $sessions=Card $rootCanvas 'SessionsCard' ($bannerHeight+$meetingHeight+$meetingGap) $sessionHeight;$c=$sessions.canvas;$w=$c.Width
 $all=@();foreach($source in @($data.codex,$data.claude)){if(Fresh $source 180){$all+=@($source.sessions)}}
 $active=@($all|Where-Object status -ne 'idle'|Sort-Object @{Expression={if($_.status -eq 'waiting'){0}elseif($_.status -eq 'working'){1}else{2}}},@{Expression='at';Descending=$true});$completed=@($all|Where-Object status -eq 'idle'|Sort-Object at -Descending)
 $waiting=@($active|Where-Object status -eq 'waiting').Count;$working=@($active|Where-Object status -eq 'working').Count
 CardHeading $c 'СЕССИИ' ([string]$waiting+' ждёт вас · '+$working+' работает')
 $scroll=[Windows.Controls.ScrollViewer]::new();$scroll.Name='SessionList';$scroll.Width=$w;$scroll.Height=[Math]::Max(28,$c.Height-24);$scroll.VerticalScrollBarVisibility='Hidden';$scroll.HorizontalScrollBarVisibility='Disabled';$stack=[Windows.Controls.StackPanel]::new();$scroll.Content=$stack;Put $c $scroll 0 24;$script:sessionScroll=$scroll
 $display=@($active);if($showCompleted){$display+=@($completed)}
 foreach($session in $display){
  $row=FlatButton '' $w {param($s,$e) OpenSession $s.Tag};$row.Name='SessionRow';$row.Tag=$session.id;$row.Height=31;$row.Padding='0'
  $grid=[Windows.Controls.Grid]::new();$grid.Width=$w;$left=[Windows.Controls.ColumnDefinition]::new();$right=[Windows.Controls.ColumnDefinition]::new();$right.Width=[Windows.GridLength]::new(88);[void]$grid.ColumnDefinitions.Add($left);[void]$grid.ColumnDefinitions.Add($right)
  $line=[Windows.Controls.StackPanel]::new();$line.Orientation='Horizontal';$line.VerticalAlignment='Center';[void]$line.Children.Add((StatusGlyph $session.status));$name=if($session.title){$session.title}else{$session.project};$title=Label $name 11 '#E5E8EB';$title.Width=[Math]::Max(40,$w-110);[void]$line.Children.Add($title);[void]$grid.Children.Add($line)
  $status=switch($session.status){'waiting'{'ждёт вас'}'working'{'работает'}'idle'{'завершена'}default{'неизвестно'}};$color=switch($session.status){'waiting'{'#76B6EF'}'working'{'#99ADA9'}'idle'{'#E6B66B'}default{'#939DA7'}}
  if($session.rate.level -in @('warning','critical')){$status='↑ расход ×'+$session.rate.ratio;$color='#E6B66B'}
  $state=Label $status 10 $color;$state.VerticalAlignment='Center';$state.TextAlignment='Right';[Windows.Controls.Grid]::SetColumn($state,1);[void]$grid.Children.Add($state);$row.Content=$grid;$row.ToolTip=$session.provider+' · '+$name
  $row.IsEnabled=$session.provider -eq 'Codex' -and $session.id -match '^[0-9a-f-]{36}$';[void]$stack.Children.Add($row)
 }
 if(-not $display.Count){[void]$stack.Children.Add((Label $(if($stale){'Список сессий устарел'}else{'Нет активных сессий'}) 12 '#939DA7'))};$scroll.ScrollToVerticalOffset($offset)
 $resource=Card $rootCanvas 'ResourcesCard' ($bannerHeight+$h-$resourceHeight) $resourceHeight;$c=$resource.canvas;$w=$c.Width;$script:resourceBorder=$resource.border
 CardHeading $c 'ОСТАТОК НЕДЕЛИ' $(if($narrow){''}else{'Лимиты подписок'})
 $gap=if($narrow){16}else{24};$half=($w-$gap)/2;$detailShift=if($narrow){36}else{0}
 for($i=0;$i -lt 2;$i++){
  $provider=@('Codex','Claude')[$i];$remaining=WeeklyRemaining $provider;$x=$i*($half+$gap);$accent=if($null -ne $remaining -and $remaining -le 15){'#E6B66B'}else{'#E5E8EB'}
  Put $c (Label $provider 11 '#939DA7') $x $(if($narrow){24}else{34})
  $value=if($null -eq $remaining){'—'}else{('{0:0.#}%' -f $remaining)};$label=Label $value 23 $accent;$label.FontFamily='Bahnschrift';$label.Name=$provider+'Remaining';$label.ToolTip=if($provider -eq 'Claude'){'Точная квота Claude недоступна. Сессии и расход читаются из ваших журналов.'}else{'Остаток из Codex app-server, если доступен вашему аккаунту.'};$label.Width=if($narrow){$half}else{$half-43};$label.TextAlignment=if($narrow){'Left'}else{'Right'};Put $c $label $(if($narrow){$x}else{$x+43}) $(if($narrow){41}else{25})
  $bar=[Windows.Controls.ProgressBar]::new();$bar.Width=$half;$bar.Height=3;$bar.Maximum=100;$bar.Value=if($null -eq $remaining){0}else{$remaining};$bar.Foreground=Brush '#A8BECD';$bar.Background=Brush '#343D47';$bar.BorderThickness=0;Put $c $bar $x $(if($narrow){70}else{59})
  $reset=$null;try{if($provider -eq 'Codex' -and $data.limits.weekly_reset_at){$reset=[DateTimeOffset]::FromUnixTimeSeconds([long]$data.limits.weekly_reset_at)}elseif($provider -eq 'Claude' -and $data.claude.limits.seven_day.resets_at){$reset=EventTime $data.claude.limits.seven_day.resets_at}}catch{}
  $resetText=if($null -eq $remaining){'Квота недоступна'}elseif($reset){'Обновится '+$reset.ToOffset([TimeSpan]::FromHours(3)).ToString('dd.MM · HH:mm')}elseif($remaining -eq 0){'Исчерпан · дата неизвестна'}else{'Дата обновления неизвестна'}
  $label=Label $resetText 9 $(if($null -ne $remaining -and $remaining -eq 0){'#E6B66B'}else{'#939DA7'});$label.Width=$half;$label.ToolTip=$resetText;Put $c $label $x $(if($narrow){79}else{68})
 }
 Divider $c $(if($narrow){102}else{91})
 $minutes=if($burn.window_seconds){[int]($burn.window_seconds/60)}else{15};$color=if($hot){'#E6B66B'}else{'#E5E8EB'}
 $rate=Label $(if($valid){(Num $burn.per_min)+' ток/мин'}else{'Нет свежих данных'}) 16 $color;$rate.FontFamily='Bahnschrift';if($narrow){$rate.Width=$w-50;$rate.ToolTip=$rate.Text};Put $c $rate 0 $(if($narrow){114}else{102})
 $hint=if(-not $valid){'Расход неизвестен'}elseif($burn.level -eq 'idle'){'Простой · '+$minutes+' мин'}elseif($null -eq $burn.baseline_per_min){'Мало истории · '+$minutes+' мин'}else{'×'+$burn.ratio+' · за '+$minutes+' мин'}
 $hintLabel=Label $hint 10 $(if($hot){'#E6B66B'}else{'#939DA7'});$hintLabel.Width=if($narrow){$w}else{118};$hintLabel.TextAlignment=if($narrow){'Left'}else{'Right'};Put $c $hintLabel $(if($narrow){0}else{$w-118}) $(if($narrow){136}else{105})
 $bars=@($burn.series);$peak=($bars|Measure-Object per_min -Maximum).Maximum
 if($valid -and $bars.Count){
  $spark=[Windows.Shapes.Polyline]::new();$spark.Stroke=Brush $(if($hot){'#E6B66B'}else{'#939DA7'});$spark.StrokeThickness=1.2;$spark.ToolTip='Динамика за день · интервалы 15 мин'
  for($j=0;$j -lt $bars.Count;$j++){$level=if($peak -gt 0){18*$bars[$j].per_min/$peak}else{0};[void]$spark.Points.Add([Windows.Point]::new(44*$j/[Math]::Max(1,$bars.Count-1),20-$level))};Put $c $spark $(if($narrow){$w-44}else{$w-165}) $(if($narrow){113}else{101})
 }
 $more=FlatButton '' $w {$script:showDetails=-not $showDetails;Draw};$more.Name='DetailsToggle';$more.Height=22;$text=Label ('Расход за день и сессии '+$(if($showDetails){'⌃'}else{'›'})) 10 '#939DA7';$text.Width=$w;$more.Content=$text;Put $c $more 0 (126+$detailShift)
 if($hot -or $showDetails){
  Divider $c (153+$detailShift)
  $leader=@($burn.leaders|Select-Object -First 1)
  $caption=if($hot -and $burn.ratio){'↑ Расход выше обычного в '+$burn.ratio+' раза'}elseif($hot){'↑ Ускорился отдельный сеанс'}else{'День · интервалы 15 мин'}
  $captionText=Label $caption 10 $(if($hot){'#E6B66B'}else{'#939DA7'});$captionText.Width=$w;$captionText.ToolTip=$caption;Put $c $captionText 0 (161+$detailShift)
  if($valid -and $leader.Count){$lead=$leader[0];$row=FlatButton '' $w {param($s,$e) OpenSession $s.Tag};$row.Name='TokenLeader';$row.Tag=$lead.id;$row.ToolTip=$lead.title;$row.Height=21;$text=Label ('№1 '+$(if($burn.leader_basis -eq 'day'){(Num $lead.day_tokens)+' за день'}else{(Num $lead.per_min)+'/мин'})+' · '+$lead.title+' ↗') 10 '#BFB7A8';$text.Width=$w;$row.Content=$text;Put $c $row 0 (179+$detailShift)}
  $codexDay=if((Fresh $data.codex 180) -and $data.codex.tokens){Num ($data.codex.tokens.input+$data.codex.tokens.output)}else{'—'};$claudeDay=if((Fresh $data.claude 180) -and $data.claude.tokens){Num ($data.claude.tokens.input+$data.claude.tokens.output)}else{'—'}
  $daily=Label ('За день · Codex '+$codexDay+' · Claude '+$claudeDay) 10 '#939DA7';$daily.Name='DailyProviderTotals';$daily.Width=$w;$daily.ToolTip=$daily.Text+' токенов с учетом кэша';Put $c $daily 0 (202+$detailShift)
  # Detailed daily chart opens in a tooltip, leaving the main card calm.
  $chart=[Windows.Controls.Canvas]::new();$chart.Width=300;$chart.Height=65;$bars=@($burn.series);$peak=($bars|Measure-Object per_min -Maximum).Maximum
  if($valid -and $bars.Count){$bw=300.0/$bars.Count;for($j=0;$j -lt $bars.Count;$j++){$bar=$bars[$j];$bh=if($peak -gt 0){[Math]::Max(2.0,60*$bar.per_min/$peak)}else{2};$rect=[Windows.Shapes.Rectangle]::new();$rect.Width=[Math]::Max(1.0,$bw-1);$rect.Height=$bh;$rect.Fill=Brush $(if($bar.level -in @('warning','critical')){'#E6B66B'}else{'#A8BECD'});Put $chart $rect ($j*$bw) (63-$bh)}}
  $more.ToolTip=$chart
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
