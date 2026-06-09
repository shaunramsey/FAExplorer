# June 4th, 2026
* Changed color settings to have palettes for the user to choose from and added more color settings
* Fixed halt and accept states so they properly halt
* Changed curved line indexing again to fix imports and exports
* Added a slider to the level select screen for keyboard and mouse
* Changed the level select screen to make everything look a lot cleaner

# June 3rd, 2026
* Added in more levels and made the level select screen more linear
* Changed a lot of the colors to make everything have a more central theme

# June 2nd, 2026
* Added in game mode to allow the user to solve levels with equivalency check requirements

# June 1st, 2026
* Fixed blackbox logic to make them import and export properly
* Fixed more blackbox logic to make them properly end and begin their cursors
* Added ~ jumps in TM mode so that they can be taken no matter what input and do not do anything
* Removed black box descriptions
* Added in a way to check for machine equivalencies
* Worked on implementing game logic

# May 28th, 2026
* Implemented blackboxes so that you can import your code as usable small pieces
* Made it so TMs do not do automatic computations to allow for infinite loops to be placed 

# May 27th, 2026
* Implemented turing machines with their own mode
* Changed the UI for batch simulator

# May 26th, 2026
* Implemented a new mode for pushdown automata so you can add and remove from a stack
* Got rid of mixed results as it was incorrect
* Made it so you cannot have an infinite loop for PDA 
* Made it so PDAs take into account hint text and duplicates
* Edited drawer UI for a better user experience
* Added in connection to firebase to let a user have saved data
* Fixed import and export for halt and accept, halt and reject, and PDA
* Fixed an issue with null jumps
* Fixed start state to make it more mobile friendly

# May 25th, 2026
* Refactored all of the code to improve its readability
* Added in shared preferences
* Created a mini-login to work on firebase tomorrow
* Made it so you can pan the screen 
* Moved reset into the drawer
* Changed halt and reject and halt and accept to not place lines out of them
* Added in a better animation for screen simulator
* Made it so that the full pathway is shown when a valid pathway is taken

# May 21st, 2026
* Added in a halt and accept and halt and reject state with string simulation capabilities
* Added in an SVG import and export to allow users to export their images
* Moved string simulator out of the drawer and gave it a visibility toggle
* self linked nodes now import and export their angle
* added in a batch string simulator to test multiple strings at once for validity

# May 20, 2026
* Added in an import and export with simple language and an export history feature
* Changed it so that start arrows are placed on tapdown rather than panning
* Fixed duplicate label issues so all duplicates are highlighted in orange
* Add in a string simulator that the user can provide a string and see if their finite automata accepts or rejects it
* fixed an issue with line textboxes so now you can click wherever on a textbox to put your cursor there

# May 19, 2026
* Added a hamburger menu for the user to view a help menu, the changelog, version history, and an About
* Tweaked the selfnode textboxes for improved readability 
* lines now end their rendering at the base of the arrow and are centered more with the arrow
* Changed all the text fonts to Courier New to have equal spacing for everything
* Nodes now turn orange to warn the user if they are about to have duplicate node labels
* delete mode now works for start lines and highlights everything in red including hint text
* start lines have a default position of being to the top left corner of a node
* Fixed a known rubberbanding issue when switching to and from linemode (also changed rubberbanding slighly)

# May 18, 2026
* Made self connecting nodes and start nodes possible
* Changed alt to shift instead to prevent browser focus issues
* Added rubberbanding so you can now see where you are placing a line
* Added a delete mode
* Fixed a minor bug with node IDs
* Fixed line textboxes
* Deleted the notifiers.dart file as it was unnecessary
* Added in a start_arrow file for your starting node and added in a button to put you in start node mode


# May 14, 2026
* Refactored the code to make everything a lot smoother for later coding
* Fixed bug related to line textboxes so you can click through a lines textbox and drag it
* Textboxes for lines are properly rendering and not coliding with the line as much
* You can now do \[\[COMMAND]] to make a properly add in non-typeable characters
* Nodes and lines have hint text, node hint text is the character it was rendered with


# May 13, 2026
* Keyboard - alt for drawing lines
* Bug Fix: Bending Lines / Click Through
* Added textboxes and made the circles transparent

# May 12, 2026
* Bending Lines