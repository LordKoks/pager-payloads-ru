📦 Русифицированные пейлоады для WiFi Pineapple Pager
Полный архив скриптов, извлечённых из прошивки и адаптированных для работы с русским интерфейсом.
Пейлоады разбиты по каталогам согласно стандартной структуре Pineapple Pager.

🗂 Категории
alerts
Автоматические оповещения при событиях в эфире.
deauth_flood_detected, handshake_captured (deduplicate, handshake‑ssid, handyshake, hashtopolis‑autocrack), pineapple_auth_captured, pineapple_client_connected (device_profiler)

misc
Разное.
BluetoothScanner

recon/access_point
Атаки и разведка на точках доступа: деаутентификация, клонирование, PMKID, WPS, сканирование скрытых сетей.
5GHzHunter, AuthFlood, AutoPwn, DeauthStorm, EvilTwin, MassDeauth, PMKIDGrabber, TargetedDeauth, WifiJammer, WPSScanner и др.

recon/client
Пассивный сбор данных о клиентах, фишинг, атаки на клиентов.
Banshee, BeaconSpam, ClientTracker, DroneHunter, IoTScanner, ProbeHunter, SocialMapper, Wraith и др.

recon/common
Общие утилиты: аудит, бэндвид‑мониторинг, туннелирование, управление пакетами, синхронизация добычи.
AuditReporter, BandwidthAlert, C2Beacon, FirewallManager, LootSync, PacketReplay, WiFiTimeline и др.

user/alerts
Настраиваемые пользовательские оповещения.
BandwidthAlert, ClientAlert, DeauthAlert, GeoFenceAlert, IntrusionAlert, RogueAPAlert

user/attack
Точечные атаки: деаутентификация конкретного клиента, создание подставных точек доступа, перехват паролей.
CaptivePortal, EvilTwin, HotspotHijack, KarmaAttack, PMKIDGrabber, TargetedDeauth, WiFiAutoPwn и др.

user/automation
Автоматизация повторяющихся действий.
AutoPwn, Reaper, ScheduledScan, TimeBomb, ZeroClick

user/blue‑team
Инструменты защиты и аудита.
AuditReporter, ComplianceAuditor, DeauthForensics, RogueDetector, WirelessIDS и др.

user/capture
Захват учётных данных и рукопожатий.
CredSniffer, EAPHarvester, HandshakeHunter, PMKIDCapture, WPACracker

user/evil_portal
Управление подставным порталом (установка, включение/выключение, смена интерфейса).
install_evil_portal, enable_evil_portal, start_evil_portal, set_evil_portal_interface и др.

user/examples
Примеры использования UI‑компонентов (ALERT, PROMPT, NUMBER_PICKER, MAC_PICKER и т.д.).
Идеально подходят для изучения DuckScript‑диалогов.

user/exfiltration
Эксфильтрация добычи: облачные загрузки, DNS‑туннели, Wigle‑тулкит.
CloudExfil, DataVacuum, DNSExfil, ICMPTunnel, LootSync, auto_hcx_capture, wigle‑toolkit и др.

user/games
Игры и развлечения для пейджера.
1988, Heads_or_Tails, neon_bikes, NumberCracker, PagerPong, Puzzle_Squirrel, text_adventure_llm и др.

user/general
Широкий спектр полезных утилит: диагностика сети, проверка GPS, просмотр логов, обновление тем/рингтонов/пейлоадов, погода, whois и пр.
AddSSIDFile, BT_Pager_Warden, gps-checker, log_viewer, MAC_spoofer, SpeedTest, Weather, whois, UpdatePayloads, UpdateThemes и др.

user/interception
Перехват и анализ трафика.
ARPSpoof, DNSSiphon, MITMProxy, PacketSniffer, SSLStrip, goodportal_

user/pranks
Шуточные атаки и пранки.
BeaconSpam, NetParasite, RickRoll, SSIDPranks, WiFiConfuser

user/reconnaissance
Продвинутая разведка: OSINT, поиск устройств, мониторинг сигнала, Shodan‑запросы.
alien_ap, blue_clues, device_hunter, flipper_detector, huginn, jelly_sentinel, TRIG_MAC_2.0, verdandi, OSINT‑U‑Asked, wifi_guppy и др.

user/remote
Удалённые подключения и управление.
C2Beacon, PagerLink, TunnelRat, VPNConnect

user/remote_access
Различные способы удалённого доступа к самому пейджеру.
tailscale, Pager_quack, Reverse_Shell, hidx_stealthlink_client, pagecord и др.

user/social
Социальная инженерия через WiFi.
CoffeeShopAttack, FakeUpdate, NullSecDeface, NullSecPortal, PortalMaster, SurveyPortal

user/stealth
Скрытные техники: маскировка, заметание следов, призрачные сети.
GhostNetwork, Honeypot, LogWiper, MACRotator, Mimic, Phantom, Poltergeist, Wraith и др.

user/utility
Служебные утилиты: оптимизация загрузки, управление пакетами, смена MAC, speedtest и т.п.
BootOptimizer, ChannelCongestion, FirewallManager, MACChanger, PackageManager, SpeedTest, WordlistManager и др.

user/virtual_pager
Твики для виртуального пейджера.
pager_skinner, virtual_pager_enhancer

🚀 Быстрая установка
Скопируйте все пейлоады в стандартную директорию на Пейджере:

bash
scp -r pager_full_backup/overlay/upper/root/payloads/* root@172.16.52.1:/root/payloads/
После копирования перезапустите интерфейс:

bash
ssh root@172.16.52.1 "killall -9 pineapple; sleep 2; /pineapple/pineapple &"
Не забудьте убедиться, что все скрипты имеют Unix‑окончания строк (LF), а права на выполнение (chmod +x) установлены.

