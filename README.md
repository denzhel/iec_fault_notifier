# Israel Electric Corporation Fault Notifier

If you want to be alerted about electriciy faults at your address, you can go to this link:
```
https://www.iec.co.il/pages/electricityfaults.aspx
```
Fill in the form and get the information.

Instead, use this script:
```
./iec_fault_notifier.sh --bot-token=<TelegramBotToken> --channel-name=<TelegramChannelName>
```
At the moment the script is hard coded to retrieve faults for my address.
You can use Developer tools while sending the form above to get these fields:
```
CityID
AddressID
HouseID
DistrictID
```
To create a Telegram Channel/ Bot, search google for BotFather.
