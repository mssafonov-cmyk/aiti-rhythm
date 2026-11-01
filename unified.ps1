# One desktop dashboard. Shared collector and physical cube stay unchanged.
$script:showCompleted=$true
$script:signalKey=''
$script:showDetails=$false
$script:cardSignals=@{}
$script:agyQuotaGroup='gemini'
. (Join-Path $assetRoot 'usage-history.ps1')
$script:quotaBarTemplate=[Windows.Markup.XamlReader]::Parse(@'
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="ProgressBar">
 <Grid SnapsToDevicePixels="True" ClipToBounds="True">
  <Border x:Name="PART_Track" Background="{TemplateBinding Background}" CornerRadius="2"/>
  <Border x:Name="PART_Indicator" Background="{TemplateBinding Foreground}" CornerRadius="2" HorizontalAlignment="Left"/>
 </Grid>
</ControlTemplate>
'@)
function QuotaBar($name,$width,$value,$color,$track){
 $bar=[Windows.Controls.ProgressBar]::new();$bar.Name=$name;$bar.Width=$width;$bar.Height=4;$bar.Maximum=100;$bar.Value=$value
 $bar.Template=$script:quotaBarTemplate;$bar.Foreground=Brush $color;$bar.Background=Brush $track;$bar.BorderThickness=0;$bar.SnapsToDevicePixels=$true
 return $bar
}
function AgyBucket($period,$group=''){
 if(-not $group){$group=$script:agyQuotaGroup};$source=$data.antigravity
 if($source.enabled -eq $false -or -not $source.quota_at -or (NowSeconds)-$source.quota_at -ge 86400){return $null}
 $bucket=$source.quota.($group+'-'+$period)
 if($null -eq $bucket.remaining_fraction -or ($bucket.reset_at -and $bucket.reset_at -le (NowSeconds))){return $null};return $bucket
}
function AgyGroup{
 if(AgyBucket 'weekly'){return $script:agyQuotaGroup}
 foreach($group in @('gemini','3p')){if(AgyBucket 'weekly' $group){return $group}};return ''
}
function AgyQuotaHeight{if(AgyGroup){return 44};return 0}
function ShowAgyGroups($sender){
 $menu=[Windows.Controls.ContextMenu]::new()
 $menu.Background=Brush '#1C232C';$menu.Foreground=Brush '#E5E8EB';$menu.BorderBrush=Brush '#3A4652'
 foreach($group in @('gemini','3p')){
  $bucket=AgyBucket 'weekly' $group;if(-not $bucket){continue}
  $item=[Windows.Controls.MenuItem]::new();$item.Header=$(if($group -eq 'gemini'){'Gemini'}else{'Другие модели'})+(' · {0:0.#}%' -f (100*$bucket.remaining_fraction));$item.Tag=$group
  $item.Add_Click({param($s,$e) $script:agyQuotaGroup=$s.Tag;Draw;SaveState});[void]$menu.Items.Add($item)
 };$sender.ContextMenu=$menu;$menu.PlacementTarget=$sender;$menu.IsOpen=$true
}
function WeeklyRemaining($provider){
 if($provider -eq 'Codex'){
  if((Fresh $data.limits) -and $null -ne $data.limits.weekly_pct){return [Math]::Max(0.0,[Math]::Min(100.0,100*(1-[double]$data.limits.weekly_pct)))}
 }elseif($data.claude.enabled -ne $false -and $data.claude.limits_at -and $null -ne $data.claude.limits.seven_day.used_percentage){
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
 }elseif($data.claude.enabled -ne $false -and $data.claude.limits_at -and $null -ne $data.claude.limits.five_hour.used_percentage){
  return [Math]::Max(0,[Math]::Min(100,100-[double]$data.claude.limits.five_hour.used_percentage))
 };return $null
}
function ClaudeQuotaStale($window='seven_day'){
 $source=$data.claude
 $reset=$source.limits.$window.resets_at
 return ($source.limits_cached -or $source.limits_error -or -not (Fresh $source) -or -not $source.limits_at -or (NowSeconds)-$source.limits_at -ge 600 -or ($reset -and (EventTime $reset) -le [DateTimeOffset]::FromUnixTimeSeconds([long](NowSeconds))))
}
function ClaudeQuotaTip($window='seven_day'){
 $source=$data.claude;$short=$window -eq 'five_hour';$value=$source.limits.$window.used_percentage
 if($null -eq $value -or -not $source.limits_at){return 'Квота Claude пока не получена.'}
 $tip='Claude · '+$(if($short){'5 часов'}else{'неделя'})+(' · остаток {0:0.#}%' -f (100-$value))
 $tip+="`nПолучено "+[DateTimeOffset]::FromUnixTimeSeconds([long]$source.limits_at).ToLocalTime().ToString('dd.MM.yyyy HH:mm')
 if(ClaudeQuotaStale $window){$tip+="`n* Последнее известное значение; текущий остаток не подтверждён."}
 $reset=$source.limits.$window.resets_at
 if($reset){$tip+="`nСброс "+(EventTime $reset).ToString('dd.MM.yyyy HH:mm');if((EventTime $reset) -le [DateTimeOffset]::FromUnixTimeSeconds([long](NowSeconds))){$tip+="`nЭто значение предыдущего окна лимита."}}
 if($source.limits_retry_at -gt (NowSeconds)){$tip+="`nПовтор не раньше "+[DateTimeOffset]::FromUnixTimeSeconds([long]$source.limits_retry_at).ToLocalTime().ToString('dd.MM HH:mm:ss')}
 if($source.limits_error -eq 'rate_limited'){$tip+="`nСервис ограничил частоту запросов (429)."}
 return $tip
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
function QuotaHeight($narrow){if(-not (ViewOption 'limits')){return 91};return $(if(ViewOption 'usage'){190}else{150})}
function DrawQuota($c,$narrow){
 $w=$c.Width;$outer=$c;CardHeading $c $(if(ViewOption 'limits'){'ОСТАТОК НЕДЕЛИ'}else{'ТОКЕНЫ ЗА СЕГОДНЯ'}) ''
 if(ViewOption 'usage'){$more=FlatButton $(if(DetailsExpanded (ViewOption 'compact_usage')){'⌃'}else{'⌄'}) 25 {$script:showDetails=-not $showDetails;Draw};$more.Name='DetailsToggle';$more.Height=19;$more.ToolTip='График скорости и самая затратная сессия';if((UsageData).burn.alert){$more.ToolTip+="`n"+(BurnNoticeText (UsageData).burn);$more.Foreground=Brush '#E6B66B'};Put $c $more ($w-25) -3}
 $group=AgyGroup;$providers=@('Codex','Claude','Antigravity');$stacked=$true;$shift=7;$gap=6;$slot=($w-$gap*2)/3;$cell=$slot-12;$footer=73
 for($i=0;$i -lt $providers.Count;$i++){
  $provider=$providers[$i];$agy=$provider -eq 'Antigravity';$x=0;$stale=$false
  $tile=FlatButton '' $slot {param($s,$e) ShowUsageHistory $s.Tag};$tile.Name='HistoryOpen'+$provider;$tile.Tag=$provider.ToLowerInvariant();$tile.Padding='6,0';$tile.Height=(QuotaHeight $narrow)-20;$tile.Background=Brush '#252F3B'
  $c=[Windows.Controls.Canvas]::new();$c.Width=$cell;$c.Height=$tile.Height;$tile.Content=$c
  $tile.ToolTip='История '+$provider+' · неделя, месяц, всё время';[Windows.Automation.AutomationProperties]::SetName($tile,'История токенов '+$provider);Put $outer $tile ($i*($slot+$gap)) 20
  if($agy){
   $bucket=AgyBucket 'weekly' $group;$left=if($bucket){100*$bucket.remaining_fraction}else{$null};$shortBucket=AgyBucket '5h' $group;$short=if($shortBucket){100*$shortBucket.remaining_fraction}else{$null};$stale=$bucket -and (NowSeconds)-$data.antigravity.quota_at -ge 600
   $reset=if($bucket.reset_at){[DateTimeOffset]::FromUnixTimeSeconds([long]$bucket.reset_at).ToLocalTime()}else{$null}
   $tip='Antigravity · '+$(if($group -eq 'gemini'){'Gemini'}else{'Другие модели'})+(' · неделя {0:0.#}%' -f $left)
   foreach($period in @(@('weekly','неделя'),@('5h','5 часов'))){$b=AgyBucket $period[0] $group;if($b){$tip+="`n"+$period[1]+(' · {0:0.#}%' -f (100*$b.remaining_fraction));if($b.reset_at){$tip+=' · сброс '+[DateTimeOffset]::FromUnixTimeSeconds([long]$b.reset_at).ToLocalTime().ToString('dd.MM HH:mm')}}}
   $tip+="`nПолучено от agy: "+[DateTimeOffset]::FromUnixTimeSeconds([long]$data.antigravity.quota_at).ToLocalTime().ToString('dd.MM HH:mm')+$(if($stale){"`n* Сохранённый остаток; откройте agy для обновления."}else{''})
   if(-not $bucket){$tip='Квота Antigravity пока не получена. История токенов доступна независимо от квоты.'}
   $name=FlatButton '' $cell {param($sender,$e) ShowAgyGroups $sender};$caption=Label $(if($group){$(if($group -eq 'gemini'){'Gemini'}else{'Другие'})+' ▾'}else{'Antigravity'}) 10 '#B6C6D4';$caption.Name='LegendAntigravity';$caption.Width=$cell;$name.Content=$caption;$name.Name='AgyQuotaGroup';$name.Height=18;$name.HorizontalContentAlignment='Left';$name.Padding='0';$name.ToolTip=$tip;$name.IsHitTestVisible=[bool]$group;Put $c $name 0 5
  }else{
   $left=WeeklyRemaining $provider;$short=FiveHourRemaining $provider;$reset=QuotaReset $provider 'weekly';$tip=if($null -eq $left){'Недельная квота недоступна в выбранном источнике.'}else{'Остаток недельной квоты '+$provider}
   $name=Label $provider 10 '#B6C6D4';$name.Name='Legend'+$provider;$name.Width=$cell;Put $c $name 0 5
   if($provider -eq 'Codex' -and $data.limits.account_label -eq 'Рабочий'){$name.Text='Codex · раб.';$name.ToolTip='Квота рабочего аккаунта Codex'}
   if($provider -eq 'Claude'){$stale=ClaudeQuotaStale;$tip=ClaudeQuotaTip}
  }
  $value=Label $(if($null -eq $left){'—'}else{('{0:0.#}%' -f $left)+$(if($stale){'*'}else{''})}) $(if($cell -lt 80){20}else{22}) $(if($stale){'#ADB8C3'}elseif($null -ne $left -and $left -le 15){'#E6B66B'}else{'#E5E8EB'})
  $value.Name=$provider+'Remaining';$value.FontFamily='Bahnschrift';$value.Width=if($stacked){$cell}else{$cell-43};$value.TextAlignment=if($stacked){'Left'}else{'Right'};$value.ToolTip=$tip
  Put $c $value 0 23
  $week=QuotaBar ($provider+'WeekBar') $cell $(if($null -eq $left){0}else{$left}) $(if($agy){'#99DDAA'}else{'#A8BECD'}) '#343D47';$week.Opacity=if($null -eq $left){0.35}else{1};$week.ToolTip=$tip;Put $c $week $x (50+$shift)
  if($null -ne $short){
   $bar=QuotaBar ($provider+'FiveHour') $cell $short $(if($short -le 15){'#E6B66B'}else{'#81B9E3'}) $(if($short -eq 0){'#6A5030'}else{'#343D47'})
   if($agy){$bar.ToolTip=$tip}elseif($provider -eq 'Claude'){$bar.ToolTip=ClaudeQuotaTip 'five_hour';if(ClaudeQuotaStale 'five_hour'){$bar.Opacity=0.5}}else{$shortReset=QuotaReset $provider 'session';$bar.ToolTip=('5 часов · остаток {0:0.#}%' -f $short)+$(if($shortReset){' · сброс '+$shortReset.ToString('dd.MM HH:mm')}else{' · дата сброса не передана'})}
   [Windows.Automation.AutomationProperties]::SetName($bar,('Пятичасовой лимит '+$provider));Put $c $bar $x (55+$shift)
  }
  $text=if($null -eq $left){$(if($cell -lt 80){'Нет данных'}else{'Квота недоступна'})}elseif($reset){'До '+$reset.ToString($(if($cell -lt 80){'dd.MM'}else{'dd.MM HH:mm'}))}else{$(if($cell -lt 80){'Нет даты'}else{'Дата не передана'})}
  if($provider -eq 'Claude' -and $null -ne $left -and $stale){$text=[DateTimeOffset]::FromUnixTimeSeconds([long]$data.claude.limits_at).ToLocalTime().ToString('dd.MM HH:mm')+'*'}
  $label=Label $text 9 '#939DA7';$label.Name=$provider+'Reset';$label.Width=$cell;$label.ToolTip=if($agy -or $provider -eq 'Claude'){$tip}elseif($reset){'Сброс недельной квоты: '+$reset.ToString('dd.MM.yyyy HH:mm')}else{'Источник не передал дату сброса недельной квоты.'};Put $c $label $x $footer
  $shortReset=if($agy -and $shortBucket.reset_at){[DateTimeOffset]::FromUnixTimeSeconds([long]$shortBucket.reset_at).ToLocalTime()}elseif(-not $agy){QuotaReset $provider 'session'}else{$null}
  $shortStale=if($provider -eq 'Claude'){ClaudeQuotaStale 'five_hour'}else{$stale}
  $shortText=if($null -eq $short){'5 ч: нет данных'}else{('5 ч: {0:0.#}%' -f $short)+$(if($shortStale){'*'}else{''})}
  $shortLabel=Label $shortText 10 $(if($null -ne $short -and $short -eq 0){'#E6B66B'}else{'#B6C6D4'});$shortLabel.Name=$provider+'ShortStatus';$shortLabel.Width=$cell;$shortLabel.ToolTip=if($provider -eq 'Claude'){ClaudeQuotaTip 'five_hour'}else{$tip};Put $c $shortLabel $x ($footer+16)
  $when=if($shortReset){'Сброс '+$shortReset.ToString('HH:mm')}elseif($provider -eq 'Claude' -and $data.claude.limits_error -eq 'not_available'){'Источник без квот'}else{'Ожидание данных'}
  if($shortStale -and $null -ne $short){$when=$(if($shortReset){'Сброс '+$shortReset.ToString('HH:mm')+'*'}else{'Сохранённый остаток'})}
  $whenLabel=Label $when 9 '#939DA7';$whenLabel.Name=$provider+'ShortReset';$whenLabel.Width=$cell;$whenLabel.ToolTip=$shortLabel.ToolTip;Put $c $whenLabel $x ($footer+30)
  if(-not (ViewOption 'limits')){foreach($child in @($c.Children)){if($child -ne $name){[void]$c.Children.Remove($child)}}}
  if(ViewOption 'usage'){
   $p=@((UsageData).providers|Where-Object name -eq $provider)|Select-Object -First 1
   $dailyY=if(ViewOption 'limits'){124}else{29}
   $caption=Label $(if($provider -eq 'Codex'){'ДЕНЬ · ПРОФИЛЬ'}else{'СЕГОДНЯ ↗'}) 8 '#8FA2B5';$caption.Name='DailyUsageHeading'+$provider;$caption.Width=$cell;Put $c $caption 0 $dailyY
   $text=if($null -eq $p.day_tokens){'—'}else{$(if($p.partial){'от '}else{''})+(TokenAmount $p.day_tokens)+$(if($p.cached_day){'*'}else{''})}
   $daily=Label $text $(if($cell -lt 70){12}else{15}) $(ProviderColor $provider);$daily.Name='Daily'+$provider;$daily.FontFamily='Bahnschrift';$daily.Width=$cell
   $daily.ToolTip='За сегодня: '+$(if($null -ne $p.day_tokens){'{0:N0} токенов' -f $p.day_tokens}else{'нет данных'})+$(if($p.cached_day){"`nПоследний сохранённый итог"}else{''})+$(if($provider -eq 'Codex'){"`nВсе аккаунты локального профиля. Квота выше — текущего аккаунта."}else{''})
   $tile.ToolTip=$daily.ToolTip+"`nНажмите, чтобы открыть историю и сравнение";Put $c $daily 0 ($dailyY+14)
  }
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
function DetailsExpanded($compact){return ([bool]$showDetails -xor (-not $compact))}
function UsageHeight($compact,$hot){if(DetailsExpanded $compact){return 145};return 0}
function DrawUsage($c,$y,$compact,$narrow){
 if(-not (DetailsExpanded $compact)){return}
 $w=$c.Width;$usage=UsageData;$burn=$usage.burn;$valid=(Fresh $usage 180) -and $usage.observed;$hot=$valid -and $burn.alert
 $minutes=if($burn.window_seconds){[int]($burn.window_seconds/60)}else{15}
 $providers=@($usage.providers)
 $speed=if($valid){$(if($usage.partial){'от '}else{''})+(TokenAmount $burn.per_min)+' ток/мин'}else{'нет данных'}
 $rate=Label ('Среднее за '+$minutes+' мин: '+$speed) 10 $(if($hot){'#E6B66B'}else{'#AAB7C4'});$rate.Name='TokenRate';$rate.Width=$w
 $rate.ToolTip='Средняя скорость по известным счётчикам за последние '+$minutes+' мин. Не расход за сутки.'+$(if($usage.partial){"`nПоказан минимум: у части источников неизвестна скорость."}else{''})+$(if($hot){"`n"+(BurnNoticeText $burn)}else{''});Put $c $rate 0 ($y+2)
 if(DetailsExpanded $compact){
  Divider $c ($y+23)
  $caption=Label 'Скорость за день' 9 '#AAB7C4';$caption.Width=$w*0.55;Put $c $caption 0 ($y+29)
  $allBars=@($providers|ForEach-Object {$_.series});$peak=($allBars|Measure-Object per_min -Maximum).Maximum
  $scale=Label $(if($null -ne $peak){'до '+(TokenAmount $peak)+'/мин'}else{'нет истории'}) 9 '#AAB7C4';$scale.Width=$w*0.45;$scale.TextAlignment='Right';Put $c $scale ($w*0.55) ($y+29)
  $count=($providers|ForEach-Object {@($_.series).Count}|Measure-Object -Maximum).Maximum
  foreach($p in $providers){$bars=@($p.series|Where-Object {$null -ne $_});if(-not $bars.Count){continue}
   $spark=[Windows.Shapes.Polyline]::new();$spark.Name='Graph'+$p.name;$spark.ToolTip=$p.name+' · ток/мин · интервалы 15 мин · общая шкала';$spark.Stroke=Brush $p.color;$spark.StrokeThickness=1.2
   for($j=0;$j -lt $bars.Count;$j++){$v=if($peak -gt 0){26*$bars[$j].per_min/$peak}else{0};[void]$spark.Points.Add([Windows.Point]::new(($w-2)*$j/[Math]::Max(1,$count-1),26-$v))};Put $c $spark 0 ($y+46)
  }
  $dates=@($allBars|Where-Object {$null -ne $_.at}|Sort-Object at)
  if($dates.Count){foreach($end in @(0,1)){$stamp=if($end){$dates[-1].at}else{$dates[0].at};$label=Label ([DateTimeOffset]::FromUnixTimeSeconds([long]$stamp).ToOffset([TimeSpan]::FromHours(3)).ToString('HH:mm')) 8 '#939DA7';$label.Width=$w/2;$label.TextAlignment=if($end){'Right'}else{'Left'};Put $c $label ($end*$w/2) ($y+74)}}
 }
 if(DetailsExpanded $compact){
  $start=$y+90;$label=Label $(if($hot){'↑ Расход выше обычного'}else{'Сессия с наибольшим расходом'}) 9 $(if($hot){'#E6B66B'}else{'#AAB7C4'});$label.Width=$w;Put $c $label 0 ($start+2)
  $leaderHeading=$label
  $leaders=@($burn.leaders|Select-Object -First 1)
  if($valid -and $leaders.Count){$lead=$leaders[0];$row=FlatButton '' $w {param($s,$e) OpenSession $s.Tag};$row.Name='TokenLeader';$row.Tag=$lead;$row.ToolTip=$lead.provider+' · '+$lead.title;$row.IsEnabled=([string]$lead.id -match '^[0-9a-f-]{36}$');$row.Height=35;$label=Label ($(if($lead.provider){$lead.provider+' · '}else{''})+$lead.title) 10 '#BFB7A8';$label.Width=$w;$detail=if($burn.leader_basis -eq 'day'){(TokenAmount $lead.day_tokens)+' за день'}else{(TokenAmount $lead.per_min)+' ток/мин'};$label.Text+=' · '+$detail;$row.Content=$label;Put $c $row 0 ($start+17)}else{$empty=Label 'Пока не определена' 10 '#939DA7';$empty.Width=$w;Put $c $empty 0 ($start+17)}
  if($valid -and $leaders.Count){$row.Content=$null;$box=[Windows.Controls.StackPanel]::new();$label.Text=($(if($lead.provider){$lead.provider+' · '}else{''})+$lead.title);[void]$box.Children.Add($label);$amount=Label $detail 10 '#E6B66B';$amount.Name='TokenLeaderAmount';[void]$box.Children.Add($amount);$row.Content=$box;$row.ToolTip+="`n"+$detail+$(if($lead.provider -eq 'Codex'){"`nПо всему локальному профилю Codex, включая другие аккаунты."}else{''})}
  if($valid -and $leaders.Count -and $lead.provider -eq 'Codex' -and -not $hot){$leaderHeading.Text='Лидер расхода · весь профиль Codex'}
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
 $low=@();if(ViewOption 'limits'){foreach($provider in @('Codex','Claude')){$left=WeeklyRemaining $provider;if($null -ne $left -and $left -le 5 -and ($provider -ne 'Claude' -or -not (ClaudeQuotaStale))){$low+=$provider};$short=FiveHourRemaining $provider;if($null -ne $short -and $short -le 5 -and ($provider -ne 'Claude' -or -not (ClaudeQuotaStale 'five_hour'))){$low+=($provider+'5h')}}}
 if((ViewOption 'limits') -and $data.antigravity.quota_at -and (NowSeconds)-$data.antigravity.quota_at -lt 600){foreach($period in @('weekly','5h')){$bucket=AgyBucket $period;if($bucket -and $bucket.remaining_fraction -le 0.05){$low+=('Antigravity'+$period)}}}
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
 $quotaHeight=if($limitsVisible -or $usageVisible){QuotaHeight $narrow}else{0}
 $usageHeight=if($usageVisible){UsageHeight $compactUsage $hot}else{0}
 $resourceHeight=if($limitsVisible -or $usageVisible){26+$quotaHeight+$usageHeight+$(if($usageHeight -gt 0){10}else{0})}else{0}
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
 if($data.codex.session_scope -eq 'account'){$c.Children[0].ToolTip='Codex: сессии текущего аккаунта. Других аккаунтов или без подтверждённого владельца скрыто: '+$data.codex.excluded_sessions+'.'}
 $scroll=[Windows.Controls.ScrollViewer]::new();$scroll.Name='SessionList';$scroll.Width=$w;$scroll.Height=[Math]::Max(28,$c.Height-24);$scroll.VerticalScrollBarVisibility='Hidden';$scroll.HorizontalScrollBarVisibility='Disabled';$stack=[Windows.Controls.StackPanel]::new();$scroll.Content=$stack;Put $c $scroll 0 24;$script:sessionScroll=$scroll
 $display=@($active);if($showCompleted){$display+=@($completed)}
 foreach($session in $display){
  $row=FlatButton '' $w {param($s,$e) OpenSession $s.Tag};$row.Name='SessionRow';$row.Tag=$session;$row.Height=31;$row.Padding='0'
  $grid=[Windows.Controls.Grid]::new();$grid.Width=$w;$left=[Windows.Controls.ColumnDefinition]::new();$right=[Windows.Controls.ColumnDefinition]::new();$right.Width=[Windows.GridLength]::new(88);[void]$grid.ColumnDefinitions.Add($left);[void]$grid.ColumnDefinitions.Add($right)
  $line=[Windows.Controls.StackPanel]::new();$line.Orientation='Horizontal';$line.VerticalAlignment='Center';[void]$line.Children.Add((StatusGlyph $session.status));$name=if($session.title){$session.title}else{$session.project};$badge=Label $(switch($session.provider){'Antigravity'{'A'}'Claude'{'Cl'}default{'C'}}) 9 (ProviderColor $session.provider);$badge.Width=19;[void]$line.Children.Add($badge);$title=Label $name 11 '#E5E8EB';$title.Width=[Math]::Max(25,$w-129);[void]$line.Children.Add($title);[void]$grid.Children.Add($line)
  $status=switch($session.status){'waiting'{'ждёт вас'}'working'{'работает'}'idle'{'завершена'}default{'неизвестно'}};$color=switch($session.status){'waiting'{'#76B6EF'}'working'{'#99ADA9'}'idle'{'#E6B66B'}default{'#939DA7'}}
  if($session.rate.level -in @('warning','critical')){$status='↑ расход ×'+$session.rate.ratio;$color='#E6B66B'}
  $state=Label $status 10 $color;$state.VerticalAlignment='Center';$state.TextAlignment='Right';[Windows.Controls.Grid]::SetColumn($state,1);[void]$grid.Children.Add($state);$row.Content=$grid;$row.ToolTip=$session.provider+' · '+$name
  $row.IsEnabled=$session.id -match '^[0-9a-f-]{36}$';[void]$stack.Children.Add($row)
 }
 if(-not $display.Count){[void]$stack.Children.Add((Label $(if($stale){'Список сессий устарел'}else{'Нет активных сессий'}) 12 '#939DA7'))};$scroll.ScrollToVerticalOffset($offset)
 }
 $script:resourceBorder=$null
 if($resourceHeight -gt 0){
  $resourceY=$meetingHeight+$meetingGap+$sessionHeight+$(if($sessionsVisible){10}else{0})
  $resource=Card $rootCanvas 'ResourcesCard' $resourceY $resourceHeight;$c=$resource.canvas;$script:resourceBorder=$resource.border
  if($limitsVisible -or $usageVisible){DrawQuota $c $narrow}
  if($usageHeight -gt 0){Divider $c ($quotaHeight+3);DrawUsage $c ($quotaHeight+10) $compactUsage $narrow}
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
