# Daily token history; all values originate from the collector's private archive.
$script:historyWindow=$null
$script:historyPeriod='week'
$script:historyProvider='codex'
function HistoryButton($text,$name,$width,$handler){
 $b=FlatButton $text $width $handler;$b.Name=$name;$b.Height=32;$b.FontSize=12;$b.Margin='0,0,6,0';return $b
}
function HistoryRows($provider=$script:historyProvider){
 $h=$data.usage.history.$provider
 $today=if($h.today){[datetime]::ParseExact($h.today,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)}else{[DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(3)).Date}
 $rows=@($h.days|Where-Object {$null -ne $_ -and $_.date -le $today.ToString('yyyy-MM-dd')}|Sort-Object date)
 if($provider -eq 'all'){$rows=@(foreach($key in @('codex','claude','antigravity')){$data.usage.history.$key.days})|Where-Object {$null -ne $_ -and $_.date -le $today.ToString('yyyy-MM-dd')}|Sort-Object date}
 $start=switch($script:historyPeriod){'week'{$today.AddDays(-6)}'month'{$today.AddDays(-29)}default{if($rows.Count){[datetime]::ParseExact($rows[0].date,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)}else{$today}}}
 $lookup=@{};foreach($r in $rows){$lookup[$r.date]=$r}
 if($provider -eq 'all'){
  $lookup=@{}
  foreach($key in @('codex','claude','antigravity')){foreach($r in $data.usage.history.$key.days){
   if(-not $lookup.ContainsKey($r.date)){$lookup[$r.date]=@{values=@{};total=0;partial=$false;at=0}}
   $day=$lookup[$r.date];$day.values[$key]=$r.total;$day.total+=$r.total;$day.partial=$day.partial -or $r.partial;$day.at=[Math]::Max($day.at,$r.at)
  }}
  foreach($day in $lookup.Values){if($day.values.Count -lt 3){$day.partial=$true}}
 }
 $answer=@();for($date=$start;$date -le $today;$date=$date.AddDays(1)){$r=$lookup[$date.ToString('yyyy-MM-dd')];$answer+=[pscustomobject]@{date=$date;total=$(if($r){$r.total}else{$null});partial=($r -and $r.partial);at=$(if($r){$r.at}else{$null});values=$(if($r){$r.values}else{$null})}}
 return $answer
}
function DrawHistory{
 if(-not $script:historyWindow){return}
 $name=switch($script:historyProvider){'claude'{'Claude'}'antigravity'{'Antigravity'}'all'{'Всего'}default{'Codex'}};$color=ProviderColor $name
 $script:historyWindow.Title=$name+' — история токенов';$script:historyTitle.Text=$name;$script:historyTitle.Foreground=Brush $color
 $script:historyMethod.Text='Объём токенов, не цена подписки. Codex — все аккаунты локального профиля; кэш уже во входе. Claude — с кэшем; Antigravity — вход + выход. Сегодня ещё не завершено.'
 foreach($button in $script:historyProviderButtons){$selected=$button.Tag -eq $script:historyProvider;$button.Background=Brush $(if($selected){'#35485A'}else{'#202A35'});$button.Foreground=Brush $(if($selected){'#F1F5FA'}else{'#A4B2C1'})}
 foreach($button in $script:historyPeriodButtons){$selected=$button.Tag -eq $script:historyPeriod;$button.Background=Brush $(if($selected){'#314153'}else{'#202A35'});$button.Foreground=Brush $(if($selected){'#F1F5FA'}else{'#A4B2C1'})}
 $rows=@(HistoryRows);$known=@($rows|Where-Object {$null -ne $_.total});$missing=$rows.Count-$known.Count
 $total=($known|Measure-Object total -Sum).Sum;$peak=($known|Measure-Object total -Maximum).Maximum
 $partial=@($known|Where-Object partial).Count -gt 0 -or $missing -gt 0
 $script:historyTotal.Text=if($known.Count){$(if($partial){'от '}else{''})+(TokenAmount $total)}else{'—'}
 $script:historyTotal.ToolTip=if($known.Count){('{0:N0} токенов' -f $total)}else{'Пока нет данных'}
 $script:historyCoverage.Text='Данные за '+$known.Count+' из '+$rows.Count+' дней'
 $script:historyPeak.Text=if($known.Count){'Пик за день  '+(TokenAmount $peak)}else{'История ещё не получена'}
 $period=switch($script:historyPeriod){'week'{'Последние 7 дней'}'month'{'Последние 30 дней'}default{'Вся доступная история'}}
 $script:historyRange.Text=$period+'  ·  '+$rows[0].date.ToString('dd.MM.yyyy')+' — '+$rows[-1].date.ToString('dd.MM.yyyy')+'  ·  МСК'
 $sources=if($script:historyProvider -eq 'all'){@($data.usage.history.codex,$data.usage.history.claude,$data.usage.history.antigravity)}else{@($data.usage.history.($script:historyProvider))}
 $notice=if(@($sources|Where-Object save_error).Count){'Не удалось сохранить историю на диск. Сейчас данные доступны в памяти.'}elseif(@($sources|Where-Object error).Count){'Источник временно недоступен. Показана сохранённая история.'}elseif(@($sources|Where-Object loading).Count){'Читаем историю журналов. Уже сохранённые значения доступны.'}elseif($missing -or $partial){'Пропуски — нет данных, а не ноль. «От» — сумма доступных счётчиков.'}else{'История по сохранившимся журналам и наблюдениям РИТМа.'}
 $script:historyNotice.Text=$notice
 $amounts=@{};foreach($key in @('codex','claude','antigravity')){$r=@(HistoryRows $key);$knownProvider=@($r|Where-Object {$null -ne $_.total});$sum=($knownProvider|Measure-Object total -Sum).Sum;$amounts[$key]=$sum;$script:historyCompare[$key].total.Text=if($knownProvider.Count){$(if(@($r|Where-Object {$null -eq $_.total -or $_.partial}).Count){'от '}else{''})+(TokenAmount $sum)}else{'—'}}
 $largest=($amounts.Values|Measure-Object -Maximum).Maximum;foreach($key in $amounts.Keys){$script:historyCompare[$key].bar.Value=if($largest -gt 0){100*$amounts[$key]/$largest}else{0}}
 $chart=$script:historyChart;$chart.Children.Clear();$axis=$script:historyAxis;$axis.Children.Clear()
 $viewport=[Math]::Max(520,$script:historyScroll.ActualWidth-4);$cw=[Math]::Max(10,$viewport/[Math]::Max(1,$rows.Count));$chart.Width=[Math]::Max($viewport,$cw*$rows.Count);$chart.Height=224
 $top=20;$height=166;$max=[Math]::Max(1,[double]$peak)
 foreach($f in @(0,0.5,1)){
  $line=[Windows.Shapes.Rectangle]::new();$line.Height=1;$line.Width=$chart.Width;$line.Fill=Brush '#2B3744';Put $chart $line 0 ($top+$height*(1-$f))
  $label=Label (TokenAmount ($max*$f)) 10 '#8295A8';$label.Width=65;$label.TextAlignment='Right';Put $axis $label 0 ($top+$height*(1-$f)-7)
 }
 for($i=0;$i -lt $rows.Count;$i++){
  $r=$rows[$i];$knownValue=$null -ne $r.total;$x=$i*$cw
  $holder=[Windows.Controls.Border]::new();$holder.Width=$cw;$holder.Height=$height+10;$holder.Background=Brush '#01000000';$holder.Name='HistoryDay'+$i
  $tip=$r.date.ToString('dd MMMM yyyy',[Globalization.CultureInfo]::GetCultureInfo('ru-RU'))+"`n"+$(if($knownValue){$(if($r.partial){'От '}else{''})+('{0:N0} токенов' -f $r.total)}else{'Нет данных'})
  if($script:historyProvider -eq 'all'){foreach($key in @('codex','claude','antigravity')){$tip+="`n"+$key+': '+$(if($null -ne $r.values.$key){'{0:N0}' -f $r.values.$key}else{'нет данных'})}}
  if($i -eq $rows.Count-1){$tip+="`nСегодня: день ещё не завершён."};if($r.at){$tip+="`nПолучено "+[DateTimeOffset]::FromUnixTimeSeconds([long]$r.at).ToOffset([TimeSpan]::FromHours(3)).ToString('dd.MM HH:mm')+' МСК'}
  $holder.ToolTip=$tip;[Windows.Automation.AutomationProperties]::SetName($holder,$tip)
  $bar=[Windows.Controls.Border]::new();$bar.Width=[Math]::Max(3,[Math]::Min(52,$cw-5));$bar.Height=if($knownValue){[Math]::Max(2,$height*[double]$r.total/$max)}else{2}
  $bar.VerticalAlignment='Bottom';$bar.Margin='0,0,0,10';$bar.CornerRadius='3,3,0,0';$bar.Background=Brush $(if($knownValue){$color}else{'#586777'});$bar.Opacity=if($r.partial){0.6}else{0.92};$holder.Child=$bar
  if($script:historyProvider -eq 'all' -and $r.total -gt 0){
   $stack=[Windows.Controls.Canvas]::new();$stack.Width=$bar.Width;$stack.Height=$bar.Height;$stack.VerticalAlignment='Bottom';$stack.Margin='0,0,0,10';$stack.Opacity=$bar.Opacity;$bottom=0
   foreach($pair in @(@('codex','Codex'),@('claude','Claude'),@('antigravity','Antigravity'))){$value=$r.values.($pair[0]);if($value -gt 0){$segment=[Windows.Shapes.Rectangle]::new();$segment.Width=$bar.Width;$segment.Height=$bar.Height*$value/$r.total;$segment.Fill=Brush (ProviderColor $pair[1]);Put $stack $segment 0 ($bar.Height-$bottom-$segment.Height);$bottom+=$segment.Height}}
   $holder.Child=$stack
  }
  $holder.Add_MouseEnter({param($s,$e) $s.Child.Opacity=1;$script:historyHover.Text=([string]$s.ToolTip -split "`n")[0]+'  ·  '+([string]$s.ToolTip -split "`n")[1]})
  $holder.Add_MouseLeave({param($s,$e) $s.Child.Opacity=0.8})
  Put $chart $holder $x $top
  $interval=if($rows.Count -le 7){1}elseif($rows.Count -le 31){5}else{30}
  if($i % $interval -eq 0){$label=Label ($r.date.ToString('dd.MM')) 10 '#8FA2B5';$label.Width=50;Put $chart $label ($x+2) ($top+$height+12)}
 }
 if(-not $known.Count){$empty=Label 'Пока нет истории за этот период' 17 '#9CADBF';$empty.Width=440;Put $chart $empty 30 80}
}
function ShowUsageHistory($provider){
 if($provider -notin @('codex','claude','antigravity','all')){return}
 $script:historyProvider=$provider
 if($script:historyWindow -and $script:historyWindow.IsVisible){DrawHistory;[void]$script:historyWindow.Activate();return}
 [xml]$hx=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
 Title="История токенов" Width="860" Height="720" MinWidth="680" MinHeight="680" WindowStartupLocation="CenterScreen" Background="#151D26" Foreground="#EAF1F8" FontFamily="Segoe UI" ResizeMode="CanResize" ShowInTaskbar="True">
 <Grid Margin="28,20,28,20">
  <Grid.RowDefinitions><RowDefinition Height="52"/><RowDefinition Height="42"/><RowDefinition Height="46"/><RowDefinition Height="30"/><RowDefinition Height="80"/><RowDefinition Height="66"/><RowDefinition Height="*"/><RowDefinition Height="28"/><RowDefinition Height="56"/></Grid.RowDefinitions>
  <Grid><StackPanel Orientation="Horizontal"><TextBlock x:Name="HTitle" FontFamily="Bahnschrift" FontSize="28" VerticalAlignment="Center"/><TextBlock Text=" / расход токенов" Foreground="#8295A8" FontSize="16" VerticalAlignment="Center" Margin="12,0,0,0"/></StackPanel></Grid>
  <StackPanel x:Name="HProviders" Grid.Row="1" Orientation="Horizontal" VerticalAlignment="Center"/>
  <StackPanel x:Name="HPeriods" Grid.Row="2" Orientation="Horizontal" VerticalAlignment="Center"/>
  <TextBlock x:Name="HRange" Grid.Row="3" Foreground="#97A9BB" FontSize="12"/>
  <Grid Grid.Row="4"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="230"/></Grid.ColumnDefinitions>
   <StackPanel><StackPanel Orientation="Horizontal"><TextBlock x:Name="HTotal" FontSize="38" FontFamily="Bahnschrift"/><TextBlock Text=" токенов" FontSize="13" Foreground="#97A9BB" VerticalAlignment="Bottom" Margin="4,0,0,10"/></StackPanel><TextBlock Text="ИТОГО ЗА ПЕРИОД" Foreground="#6F849A" FontSize="10"/></StackPanel>
   <StackPanel Grid.Column="1" HorizontalAlignment="Right" Margin="0,9,0,0"><TextBlock x:Name="HCoverage" FontSize="13" Foreground="#B5C4D3"/><TextBlock x:Name="HPeak" FontSize="12" Foreground="#8295A8" Margin="0,10,0,0"/></StackPanel>
  </Grid>
  <UniformGrid x:Name="HCompare" Grid.Row="5" Rows="1" Columns="3"/>
  <Grid Grid.Row="6"><Grid.ColumnDefinitions><ColumnDefinition Width="72"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Canvas x:Name="HAxis" VerticalAlignment="Top"/><ScrollViewer x:Name="HScroll" Grid.Column="1" HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Disabled"><Canvas x:Name="HChart" VerticalAlignment="Top"/></ScrollViewer></Grid>
  <TextBlock x:Name="HHover" Grid.Row="7" Text="Наведите на день, чтобы увидеть точное значение" FontSize="12" Foreground="#BDD0E0"/>
  <StackPanel Grid.Row="8"><TextBlock x:Name="HNotice" FontSize="11" TextWrapping="Wrap" Foreground="#9DAFC1"/><TextBlock x:Name="HMethod" FontSize="10" TextWrapping="Wrap" Foreground="#6F849A" Margin="0,7,0,0"/></StackPanel>
 </Grid>
</Window>
'@
 $script:historyWindow=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($hx));$script:historyWindow.Owner=$win
 $script:historyWindow.Resources=$win.Resources
 foreach($pair in @(@('historyTitle','HTitle'),@('historyRange','HRange'),@('historyTotal','HTotal'),@('historyCoverage','HCoverage'),@('historyPeak','HPeak'),@('historyChart','HChart'),@('historyAxis','HAxis'),@('historyScroll','HScroll'),@('historyHover','HHover'),@('historyNotice','HNotice'))){Set-Variable -Scope Script -Name $pair[0] -Value $script:historyWindow.FindName($pair[1])}
 $script:historyMethod=$script:historyWindow.FindName('HMethod')
 $script:historyProviderButtons=@();$script:historyCompare=@{}
 foreach($item in @(@('codex','Codex'),@('claude','Claude'),@('antigravity','Antigravity'),@('all','Всего'))){
  $b=HistoryButton $item[1] ('HistoryProvider'+$item[0]) 120 {param($s,$e) $script:historyProvider=$s.Tag;$script:historyHover.Text='Наведите на день, чтобы увидеть точное значение';DrawHistory};$b.Tag=$item[0];[void]$historyWindow.FindName('HProviders').Children.Add($b);$script:historyProviderButtons+=$b
  if($item[0] -ne 'all'){$box=[Windows.Controls.StackPanel]::new();$box.Margin='0,0,20,10';[void]$box.Children.Add((Label $item[1] 10 (ProviderColor $item[1])));$total=Label '—' 16 '#E5E8EB';[void]$box.Children.Add($total);$bar=QuotaBar ('Compare'+$item[1]) 180 0 (ProviderColor $item[1]) '#2B3744';$bar.HorizontalAlignment='Left';$bar.Margin='0,6,0,0';[void]$box.Children.Add($bar);[void]$historyWindow.FindName('HCompare').Children.Add($box);$script:historyCompare[$item[0]]=@{total=$total;bar=$bar}}
 }
 $periods=$script:historyWindow.FindName('HPeriods');$script:historyPeriodButtons=@()
 foreach($item in @(@('week','Неделя'),@('month','Месяц'),@('all','Всё время'))){$b=HistoryButton $item[1] ('HistoryPeriod'+$item[0]) 100 {param($s,$e) $script:historyPeriod=$s.Tag;$script:historyHover.Text='Наведите на день, чтобы увидеть точное значение';DrawHistory;$script:historyScroll.ScrollToRightEnd()};$b.Tag=$item[0];[void]$periods.Children.Add($b);$script:historyPeriodButtons+=$b}
 $script:historyWindow.Add_SizeChanged({DrawHistory})
 $script:historyWindow.Add_KeyDown({param($s,$e) if($e.Key -eq 'Escape'){$s.Close()}})
 $script:historyWindow.Add_Closed({$script:historyTimer.Stop();$script:historyWindow=$null})
 $script:historyTimer=[Windows.Threading.DispatcherTimer]::new();$script:historyTimer.Interval=[TimeSpan]::FromSeconds(15);$script:historyTimer.Add_Tick({DrawHistory})
 $script:historyWindow.Show();$script:historyWindow.UpdateLayout();DrawHistory;$script:historyScroll.ScrollToRightEnd();$script:historyTimer.Start()
}
