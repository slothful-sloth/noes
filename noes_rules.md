# Tabletop Sim - Partner Dominoes ("Noes")

## Assets
### 3D tiles
+ rectangular body
+ give players ability to select tile theme
+ all players will see the same tile set for the game

+ **default theme:**
	+ Puerto Rican flag on the back side
	+ black rounded inset dots/pips, not just painted flat
	+ spinner nub in the middle of the face

+ **other themes:** Classic ivory, Pip colours by number
+ **alternate backs:** Taiwan, Bangladesh, New Jersey, Albrecht Dürer's *The Four Horsemen*
+ **custom back:** any player may paste an image URL (used e.g. for Chicago Bears / New York Jets backs, which are not shipped in the repo)

### Table
+ octagonal table with maple coloured wooden borders
+ selectable image for table face: green felt, maple wood, Puerto Rico / coquí art, dark slate,
  "Suckers" in elaborate calligraphy on textured matte grey, or a custom image URL

### Hosting
+ public GitHub repo; asset URLs pinned to a commit SHA so TTS re-downloads changed assets
+ optional later move to Steam Cloud for a Workshop release


## Rules
+ double 0 through double 6 tiles (28); 7 tiles per player; no boneyard
+ two-ended line of play; doubles are placed crosswise
+ play moves counter-clockwise (to the right); partners sit opposite each other
+ a player must play if able; passing is allowed only with no legal move
+ **Lead (salida):** in the first hand of the *series*, the holder of 6/6 leads. In every later hand
  (including the first hand of later games) the winner of the previous hand leads with any tile.
+ **Dominó (winning by playing the last tile):** the winning team scores the pips in all three other hands.
+ **Capicú:** winning the hand by playing a tile that can legally match either of the two open ends of the board.
  Does not count when both open ends show the same number.
+ **Chuchazo:** winning the hand with the double-blank (0/0) tile.
+ Capicú and chuchazo never stack (a 0/0 capicú would need equal ends, which does not count).
+ **Tranque (closed game):** detected automatically when no player can move. The player with the lowest
  pip total wins; if tied, the player with fewer tiles wins; if still tied, the team who won the previous
  hand prevails (in the first hand of a series: the leader's team). The winner's team scores every pip
  left on the table, including their own.
+ **Redeal:** a player dealt 5 or more doubles may request a reshuffle.
+ **Game end:** a game ends immediately when a team reaches the target, including mid-hand via a pass bonus.
+ **Series:** best of 1, 3 or 5 games (majority wins). No pollona, no rounding.
+ create an option to choose rule sets before the game starts, display the rule set upon selection for user reference.

+ **Predefined rules:**

| | Puerto Rican rules | Custom rules |
|---|---|---|
| Target score | 500 | 300 |
| 6/6 on the series-opening lead | mandatory | holder leads, any tile |
| Premios (to the winner of hands 1–4 of each game, including tranque) | 100 / 75 / 50 / 25 | none |
| Pass bonus | 25 to the team of the player who played before the passer, banked immediately | none |
| Capicú / Chuchazo | 100 | 60 |


## Functionality
### Lobby (before the series starts)
+ Two teams, two players each; players self-assign teams and seats
+ team members can set a team name
+ players choose the series length: best of 1, 3 or 5
+ any seated player may change rule set, tile theme and table face; settings lock at the start
+ the series starts when 4 humans are seated, both teams are full and all players are ready (no bots)
+ a developer mode lets one player act for every seat (testing only)

### Sopa and draw
+ tiles start face down in the centre and may be stirred by hand
+ "Shuffle" button scatters them automatically; each player has a "Draw 7" button; manual picking also works

### Hands
+ tiles stand on edge in front of each player; the owner sees the faces, the others see the backs

### Tile placement
+ legally placed tiles should snap together on the board
+ attempting to place a tile whose numbers don't match either end of the placed tiles should show, to only that player, that the tile is rejected
+ when a user selects/clicks a tile, valid positions should be highlighted on the board, if none are available, show nothing.
+ if the active player has no legal move, they get a private notice and a "¡Paso!" button; passing plays a knock sound and moves to the next turn
+ **Taunt:** a non-active player may place a tile face down and spin it to taunt other players. The tile
  stays theirs and returns to their rack when their turn starts. They may also *commit* to playing it:
  if it is legal on their turn they must play it; if not, it flips face up for everyone ("Bluff called!")
  and stays revealed in their rack.

### Scoring
+ Upon completion of a round, game should tally up points automatically, add points from tiles, premios (if rules apply), and points from capicú or chuchazo
+ scoreboard (on-screen toggleable panel and a 3D board beside the table) should show:
	+ a line for each round showing the winning player of the round (whoever placed the last tile or winner of a tranque)
	+ tally of score for that round (pips, bonus, premio, pass bonuses)
	+ total score for the game
	+ number of games won per team in the series

### Language
+ English UI with Spanish game terms (¡Capicú!, ¡Chuchazo!, ¡Paso!, Tranque, Premio, Sopa)
