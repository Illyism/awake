# dmgbuild settings for the Awake installer window.
# Places Awake.app at (170, 178) and Applications at (490, 178) at 128pt
# over the Retina background.tiff (660×400 window).
files = [defines["app"]]
symlinks = {"Applications": "/Applications"}
background = defines["background"]
window_rect = ((200, 368), (660, 432))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 13
icon_locations = {"Awake.app": (170, 178), "Applications": (490, 178)}
