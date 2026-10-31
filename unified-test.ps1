$win.Show();Tick;$win.UpdateLayout();Draw;$results=@()
function FindControl($root,$name){
 if($root -is [Windows.FrameworkElement] -and $root.Name -eq $name){return $root}
 for($i=0;$i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($root);$i++){$found=FindControl ([Windows.Media.VisualTreeHelper]::GetChild($root,$i)) $name;if($found){return $found}}
}
function Control($name){$win.UpdateLayout();FindControl $Body $name}
function Click($button){$button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))}
function Preview($name){
 $win.UpdateLayout();$bmp=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$win.ActualWidth,[int]$win.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bmp.Render($win)
 $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp));$file=[IO.File]::Create((Join-Path $root $name));$encoder.Save($file);$file.Dispose()
}
$win.Width=380;$win.Height=580;$win.UpdateLayout();Draw;$win.UpdateLayout();Preview 'rhythm-preview.png';$small=(Control 'SessionList').ActualHeight
$win.Width=500;$win.Height=800;$win.UpdateLayout();Draw;$win.UpdateLayout();Preview 'rhythm-expanded.png';$large=(Control 'SessionList').ActualHeight
if($large -le $small+150){throw 'Session viewport did not expand'}
$results+=@{checks='unified responsive layout';small=$small;large=$large;passed=$true}
$now=NowSeconds;$time=[DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(3))
$utcExample='2026-11-02T21:30:00Z'
if((EventTime $utcExample).ToString('yyyy-MM-dd HH:mm') -ne [DateTimeOffset]::Parse($utcExample).ToLocalTime().ToString('yyyy-MM-dd HH:mm')){throw 'UTC calendar time must display in the local timezone'}
$script:selectedRef='';$script:data=[pscustomobject]@{
 limits=[pscustomobject]@{checked_at=$now;weekly_pct=0.163;weekly_reset_at=$now+86400}
 claude=[pscustomobject]@{checked_at=$now;limits_at=$now;limits=[pscustomobject]@{seven_day=[pscustomobject]@{used_percentage=100}}}
 codex=[pscustomobject]@{checked_at=$now;observed=$true;sessions=@([pscustomobject]@{id='00000000-0000-0000-0000-000000000001';provider='Codex';title='Ожидает ответа';status='waiting';at=$now},[pscustomobject]@{id='00000000-0000-0000-0000-000000000002';provider='Codex';title='Завершённая';status='idle';at=$now})}
 calendar=[pscustomobject]@{checked_at=$now;synced_at=$time.ToString('o');events=@([pscustomobject]@{ref='first';subject='Первая встреча';planned_date=$time.AddMinutes(4).ToString('o');telemost_url='https://telemost.360.yandex.ru/j/test'},[pscustomobject]@{ref='second';subject='Вторая встреча';planned_date=$time.AddMinutes(40).ToString('o');telemost_url=''})}
}
$win.Width=370;$win.Height=560;$win.UpdateLayout();Draw;$win.UpdateLayout()
$savedEvents=$data.calendar.events
$data.calendar.events=@([pscustomobject]@{ref='ongoing';planned_date=$time.AddMinutes(-20).ToString('o');planned_end=$time.AddMinutes(30).ToString('o')},$savedEvents[0])
if((NextEvent).ref -ne 'first'){throw 'An ongoing meeting must not suppress the next meeting reminder'}
$data.calendar.events=$savedEvents
$results+=@{checks='calendar local timezone and upcoming reminder over ongoing meeting';passed=$true}
if((Control 'CodexRemaining').Text -notmatch '83[.,]7%'){throw ('Precise weekly percentage missing: '+(Control 'CodexRemaining').Text+' raw '+$data.limits.weekly_pct)}
if((Control 'ClaudeRemaining').Text -notmatch '0%'){throw 'Zero remaining incorrectly treated as missing'}
if((Control 'ClaudeRemaining').ToolTip -match 'недоступна'){throw 'Available Claude quota must not be described as unavailable'}
if((Control 'SessionList').Content.Children.Count -ne 2){throw 'Completed sessions must be visible by default'}
if(Control 'CompletedToggle'){throw 'Completed toggle still occupies panel space'}
$completedMenu.IsChecked=$false;$completedMenu.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
if((Control 'SessionList').Content.Children.Count -ne 1){throw 'Settings did not hide completed'}
$completedMenu.IsChecked=$true;$completedMenu.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
if((Control 'SessionList').Content.Children.Count -ne 2){throw 'Settings did not show completed'}
if($LiveDot.Text -or $Foot.Visibility -ne 'Collapsed'){throw 'Healthy updates must not occupy space'}
$script:fixtureNow=$now;function NowSeconds{return $script:fixtureNow}
# Regression: pulse is still visible two minutes before start, long after its first six seconds.
$data.calendar.events[0].planned_date=[DateTimeOffset]::FromUnixTimeSeconds($now+120).ToString('o')
$script:cardSignals['MeetingCard']=@{key='meeting:first';at=[DateTimeOffset]::UtcNow.AddMinutes(-3)}
$script:fixtureNow=[Math]::Floor($now/2.4)*2.4;UpdateCardSignals
$brightColor=(Control 'MeetingCard').Background.Color.ToString();Preview 'rhythm-reminder-bright.png'
$script:fixtureNow+=1.2;UpdateCardSignals
$dimColor=(Control 'MeetingCard').Background.Color.ToString();Preview 'rhythm-reminder-dim.png'
if($brightColor -eq $dimColor){throw 'Meeting pulse stopped before start'}
$script:fixtureNow=$now
foreach($seconds in @(61,60,1,0,-60,-61)){
 $data.calendar.events[0].planned_date=[DateTimeOffset]::FromUnixTimeSeconds($now+$seconds).ToOffset([TimeSpan]::FromHours(3)).ToString('o');UpdateCardSignals
 $expected=$seconds -le 60 -and $seconds -ge -60
 if(((Control 'MeetingCard').BorderBrush.Color.R -eq 240) -ne $expected){throw ('Wrong red boundary: '+$seconds)}
 if($seconds -eq 60){Draw;Preview 'rhythm-minute-red.png'}
}
$data.calendar.events[0].planned_date=$time.AddMinutes(4).ToString('o');Draw

foreach($name in @('OpenMeeting','CopyMeeting')){
 $button=Control $name;$win.UpdateLayout();$point=$button.TranslatePoint([Windows.Point]::new($button.ActualWidth/2,$button.ActualHeight/2),$win);$hit=$win.InputHitTest($point)
 while($hit -and $hit -isnot [Windows.Controls.Button]){$hit=[Windows.Media.VisualTreeHelper]::GetParent($hit)}
 if($hit -ne $button){throw ('Obstructed '+$name)};Click $button
 if($script:testMeetingAction.url -ne 'https://telemost.360.yandex.ru/j/test' -or $script:testMeetingAction.copy -ne ($name -eq 'CopyMeeting')){throw 'Meeting action failed'}
}
Click (Control 'SessionRow');if($script:testSessionUrl -ne 'codex://threads/00000000-0000-0000-0000-000000000001'){throw 'Session navigation failed'}
Click (Control 'DetailsToggle');if(-not $script:showDetails){throw 'Details toggle failed'}
Click (Control 'DetailsToggle')
Preview 'rhythm-fixture.png'
Click (Control 'UpcomingMeeting');if((SelectedEvent).ref -ne 'second'){throw 'Upcoming navigation failed'}
if((Control 'OpenMeeting').IsEnabled){throw 'Missing URL should disable join'}
$script:data.limits.checked_at=$now-700;Draw;if((Control 'CodexRemaining').Text -notmatch '—'){throw 'Stale limits shown as current'}
# Check all three cards stay separated at the minimum size, including alerts.
$script:data.codex|Add-Member -NotePropertyName burn -NotePropertyValue ([pscustomobject]@{alert=$true;level='warning';ratio=2.7;per_min=252000;window_seconds=900;baseline_per_min=93333;leaders=@([pscustomobject]@{id='00000000-0000-0000-0000-000000000001';title='Самый затратный сеанс';per_min=200000})})
$script:selectedRef='';Draw;$win.UpdateLayout();Preview 'rhythm-alert.png'
foreach($pair in @(@('MeetingCard','SessionsCard'),@('SessionsCard','ResourcesCard'))){$a=Control $pair[0];$b=Control $pair[1];if([Windows.Controls.Canvas]::GetTop($a)+$a.ActualHeight -gt [Windows.Controls.Canvas]::GetTop($b)){throw 'Cards overlap'}}
if(-not (Control 'TokenLeader')){throw 'Alert must expose the leader'}
$signalTime=$script:cardSignals['ResourcesCard'].at;UpdateCardSignals;if($signalTime -ne $script:cardSignals['ResourcesCard'].at){throw 'Unchanged signal restarted pulse'}
$script:cardSignals['ResourcesCard'].at=[DateTimeOffset]::UtcNow.AddSeconds(-8);Draw
if((Control 'ResourcesCard').BorderBrush.HasAnimatedProperties){throw 'Pulse should finish'}
$script:bgAlpha=128;Draw
if((Control 'ResourcesCard').Background.Color.A -ne 128 -or (Control 'CodexRemaining').Opacity -ne 1){throw 'Transparency must affect background only'}
$script:bgAlpha=255
if($win.Title -ne 'АйТи:Ритм' -or $tray.Text -ne 'АйТи:Ритм'){throw 'Rename incomplete'}
$results+=@{checks='three cards; session navigation; details; finite alert; background-only transparency; Rhythm title';passed=$true}
Click $Hide;if($win.IsVisible){throw 'Hide failed'};$trayMenu.Items[0].PerformClick()
if(-not $win.IsVisible -or $win.ShowInTaskbar -or $script:hasConsole){throw 'Console-free tray restore failed'}
$results+=@{checks='precise percentages including zero and stale; completed toggle; meeting hit tests, copy/join, navigation; tray restore';passed=$true}
foreach($source in @($data.codex,$data.calendar,$data.limits,$data.claude)){$source.checked_at=$now-1000};Draw;$win.UpdateLayout()
if($LiveDot.Text -notmatch 'Нет обновлений'){throw 'Stopped collector needs header warning'}
if(Control 'DataStaleBanner'){throw 'Stale banner must not consume panel height'}
RecoverCollector;if(-not $script:testRecovery){throw 'Recovery action is not connected'}
Preview 'rhythm-stale.png'
$data.codex.checked_at=$now;$data.claude.checked_at=$now;$data.calendar.checked_at=$now;Draw
if($LiveDot.Text){throw 'Warning must disappear after recovery'}
$results+=@{checks='compact layout; completed settings; red boundaries 61/60/1/0/-60/-61; header stale and recovery';passed=$true}
# Narrow-width acceptance uses the actual 260-DIP viewport, not scaled text.
$win.Width=260;$win.Height=600;$script:selectedRef='';$data.codex.checked_at=$now;$data.calendar.checked_at=$now;$data.limits.checked_at=$now
$data.limits.weekly_pct=0.163;$script:showDetails=$true;Draw;$win.UpdateLayout();Draw;$win.UpdateLayout()
if($win.ActualWidth -ne 260){throw 'Minimum width still prevents compact mode'}
foreach($cardName in @('MeetingCard','SessionsCard','ResourcesCard')){
 $card=Control $cardName
 if($card.ActualWidth -gt $Body.ActualWidth+1){throw ('Clipped narrow card '+$cardName)}
}
if((Control 'CodexRemaining').Text -notmatch '83[.,]7%'){throw 'Compact percentage lost precision'}
foreach($name in @('OpenMeeting','CopyMeeting','SessionRow','DetailsToggle')){
 $button=Control $name;$point=$button.TranslatePoint([Windows.Point]::new($button.ActualWidth/2,$button.ActualHeight/2),$win);$hit=$win.InputHitTest($point)
 while($hit -and $hit -isnot [Windows.Controls.Button]){$hit=[Windows.Media.VisualTreeHelper]::GetParent($hit)}
 if($hit -ne $button){throw ('Compact control obstructed '+$name)}
}
Preview 'rhythm-narrow.png'
$results+=@{checks='260 DIP width; cards fit viewport; precise percent; meeting/session/details hit tests';passed=$true}
$data.calendar|Add-Member -NotePropertyName enabled -NotePropertyValue $false -Force
Draw;$win.UpdateLayout()
if(Control 'MeetingCard'){throw 'Disabled calendar must not leave a card'}
if([Windows.Controls.Canvas]::GetTop((Control 'SessionsCard')) -ne 0){throw 'Disabled calendar leaves an empty gap'}
if($LiveDot.Text -match 'Календарь'){throw 'Disabled calendar must not report calendar staleness'}
Preview 'rhythm-no-calendar.png'
$data.calendar.enabled=$true;Draw
if(-not (Control 'MeetingCard')){throw 'Enabled calendar must restore its card'}
if((MeetingUrl 'https://meet.google.com/abc-defg-hij') -ne 'https://meet.google.com/abc-defg-hij'){throw 'Google Meet link unsupported'}
if(MeetingUrl 'https://meet.google.com.evil.example/abc-defg-hij'){throw 'Untrusted meeting host accepted'}
$results+=@{checks='calendar off removes card/gap/warning; calendar on restores; Meet host allowlist';passed=$true}
$notice=BurnNoticeText ([pscustomobject]@{per_min=1200000;leader_basis='window';leaders=@([pscustomobject]@{title='Разбор клиентской задачи';per_min=850000})})
if($notice -notmatch 'Сессия Codex: Разбор клиентской задачи' -or $notice -notmatch 'Её расход: 850[.,]0K ток/мин'){throw 'Token alert must name the session and its own rate'}
$unknown=BurnNoticeText ([pscustomobject]@{per_min=100000;leaders=@()})
if($unknown -notmatch 'Сессию определить не удалось'){throw 'Token alert must not invent a session'}
$long=BurnNoticeText ([pscustomobject]@{per_min=100000;leader_basis='day';leaders=@([pscustomobject]@{title=('Длинное название '*20);day_tokens=2000000})})
if($long.Length -gt 240 -or $long -notmatch 'За день: 2[.,]0M токенов'){throw 'Long titles must fit the alert without confusing daily total with rate'}
$results+=@{checks='token balloon identifies session and rate; honest missing session; bounded long title; correct daily units';passed=$true}
$results|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'widget-test.json') -Encoding UTF8
$script:closing=$true;$win.Close()
