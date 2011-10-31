/*
 Copyright 2011 (C) Raster Software Vigo (Sergio Costas)

 This file is part of Cronopete

 Nanockup is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 3 of the License, or
 (at your option) any later version.

 Nanockup is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>. */

using GLib;
using Gee;
using Gtk;
using Gdk;

namespace FilelistIcons {

	struct file_info {
		string name;
		bool isdir;
		TimeVal mod_time;
		int64 size;
	}

	struct bookmark_str {
		string name;
		string icon;
	}

	class IconBrowser : Frame {

		private VBox main_container;
		private HBox buttons_path;
		private ScrolledWindow buttons_scroll;
		private ListStore path_model;
		private IconView path_view;
		private ScrolledWindow scroll;
		private string current_path;
		private Gee.List<ToggleButton> path_list;
		private EventBox background_eb;
		private time_t current_backup;
		private backends backend;
		private uint timer_refresh;
		private Menu menu;
		private bool show_hiden;
		private Gee.List<bookmark_str ?> bookmarks;
		private Gtk.TreeView bookmark_view;
		private ListStore bookmark_model;
		private Gtk.Button btn_prev;
		private Gtk.Button btn_next;
	
		public IconBrowser(backends p_backend,string p_current_path) {
	
			this.backend=p_backend;
			this.current_path=p_current_path;
		
			this.main_container=new VBox(false,0);
			this.timer_refresh=0;
			
			this.show_hiden=false;

			this.buttons_scroll=new Gtk.ScrolledWindow(null,null);
			this.buttons_scroll.hscrollbar_policy=PolicyType.NEVER;
			this.buttons_scroll.vscrollbar_policy=PolicyType.NEVER;
			this.buttons_path=new HBox(false,0);
			this.buttons_path.homogeneous=false;
			this.buttons_scroll.add_with_viewport(this.buttons_path);

			var buttons_container = new HBox(false,0);
			this.btn_prev=new Button();
			var pic1 = new Gtk.Image.from_icon_name("back",IconSize.SMALL_TOOLBAR);
			this.btn_prev.add(pic1);
			this.btn_next=new Button();
			var pic2 = new Gtk.Image.from_icon_name("forward",IconSize.SMALL_TOOLBAR);
			this.btn_next.add(pic2);
			buttons_container.pack_start(this.btn_prev,false,false,0);
			buttons_container.pack_start(this.buttons_scroll,false,false,0);
			buttons_container.pack_start(this.btn_next,false,false,0);
			this.main_container.pack_start(buttons_container,false,false,0);

			var container2 = new Gtk.HBox(false,0);
			var scroll2= new ScrolledWindow(null,null);
			scroll2.hscrollbar_policy=PolicyType.NEVER;
			this.bookmark_model=new ListStore(3,typeof(Icon),typeof(string),typeof(string));
			this.bookmark_view=new Gtk.TreeView.with_model(this.bookmark_model);
			var crpb = new CellRendererPixbuf();
			crpb.stock_size = IconSize.SMALL_TOOLBAR;
			this.bookmark_view.insert_column_with_attributes (-1, "", crpb , "gicon", 0);
			this.bookmark_view.insert_column_with_attributes (-1, "", new CellRendererText (), "text", 1);
			this.bookmark_view.enable_grid_lines=TreeViewGridLines.NONE;
			this.bookmark_view.headers_visible=false;
			this.read_bookmarks();
			this.bookmark_view.show();
			Gtk.Requisition req;
			this.bookmark_view.size_request(out req);
			this.bookmark_view.cursor_changed.connect(this.bookmark_selected);

			scroll2.add(this.bookmark_view);
			scroll2.hscrollbar_policy=PolicyType.AUTOMATIC;
			scroll2.vscrollbar_policy=PolicyType.AUTOMATIC;
			scroll2.set_size_request(req.width+40,-1);
			container2.pack_start(scroll2,false,true,0);
			
			this.scroll = new ScrolledWindow(null,null);
			this.scroll.hscrollbar_policy=PolicyType.AUTOMATIC;
			this.scroll.vscrollbar_policy=PolicyType.AUTOMATIC;
			container2.pack_start(this.scroll,true,true,0);

			this.main_container.pack_start(container2,true,true,0);
			
			/* path_model stores the data for each file/folder:
				 - file name (string)
				 - icon (string)
				 - is_folder (boolean)
			*/
			this.path_model=new ListStore(3,typeof(string),typeof(Pixbuf),typeof(bool));
			this.path_view=new IconView.with_model(this.path_model);
			this.path_view.add_events (Gdk.EventMask.BUTTON_RELEASE_MASK);
			this.path_view.button_release_event.connect(this.on_click);
			this.path_view.columns=-1;
			this.path_view.set_pixbuf_column(1);
			this.path_view.set_text_column(0);
			this.path_view.selection_mode=SelectionMode.MULTIPLE;
			this.path_view.button_press_event.connect(this.selection_made);
			this.path_view.orientation=Orientation.VERTICAL;
			this.scroll.add_with_viewport(this.path_view);
			this.background_eb = new EventBox();
			this.background_eb.add(this.main_container);
			this.add(this.background_eb);

			this.path_view.item_width=175;
		
			this.path_list=new Gee.ArrayList<ToggleButton>();
		
			this.refresh_icons();
			this.refresh_path_list();
		
		}

		private bool read_bookmarks() {

			TreeIter iter;

			this.bookmarks = new Gee.ArrayList<bookmark_str ?>();

			string home=Environment.get_home_dir();

			bookmark_str val = bookmark_str();
			val.name=home.dup();
			val.icon="user-home folder-home";
			this.bookmarks.add(val);
			
			var config_file = File.new_for_path (GLib.Path.build_filename(home,".config","user-dirs.dirs"));
			
			if (config_file.query_exists (null)) {
				try {
					var file_read=config_file.read(null);
					var in_stream = new DataInputStream (file_read);
					string line;
					string folder;
					string type;
					int pos;
					int len;

					while ((line = in_stream.read_line (null, null)) != null) {
						if (line.has_prefix("XDG_")) {
							pos=line.index_of_char('_',4);
							type=line.substring(4,pos-4);
							pos=line.index_of_char('=');
							folder=line.substring(pos+1);
							len=folder.length;
							if ((folder[0]=='"')&&(len>=2)) {
								folder=folder.substring(1,len-2);
							}
							if (folder.has_prefix("$HOME")) {
								folder=GLib.Path.build_filename(home,folder.substring(6));
							}
							val = bookmark_str();
							GLib.stdout.printf("fodler %s\n",folder);
							val.name = folder.dup();
							switch (type) {
							case "DESKTOP":
								val.icon="user-desktop";
							break;
							case "DOWNLOAD":
								val.icon="user-download folder-download folder-downloads";
							break;
							case "TEMPLATES":
								val.icon="user-templates folder-templates";
							break;
							case "PUBLICSHARE":
								val.icon="user-publicshare folder-publicshare";
							break;
							case "DOCUMENTS":
								val.icon="user-documents folder-documents";
							break;
							case "MUSIC":
								val.icon="user-music folder-music";
							break;
							case "PICTURES":
								val.icon="user-pictures folder-pictures";
							break;
							case "VIDEOS":
								val.icon="user-videos folder-videos";
							break;
							default:
								val.icon="folder";
							break;
							}
							this.bookmarks.add(val);
						}
					}
				} catch {
				}
			}

			config_file = File.new_for_path (GLib.Path.build_filename(home,".gtk-bookmarks"));
			
			if (config_file.query_exists (null)) {
				try {
					var file_read=config_file.read(null);
					var in_stream = new DataInputStream (file_read);
					string line;
					string folder;
					while ((line = in_stream.read_line (null, null)) != null) {
						if (line.has_prefix("file://")) {
							folder=line.substring(7);
						    val = bookmark_str();
							val.name = folder.dup();
							val.icon=Gtk.Stock.DIRECTORY;
							this.bookmarks.add(val);
						}
					}
				} catch {
				}
			}
			string icons;
			foreach(var folder in this.bookmarks) {
				icons="%s folder".printf(folder.icon);
				var tmp = new ThemedIcon.from_names(icons.split(" "));
				this.bookmark_model.append (out iter);
				this.bookmark_model.set(iter,0,tmp);
				this.bookmark_model.set(iter,1,GLib.Path.get_basename(folder.name));
				this.bookmark_model.set(iter,2,folder.name);

			}
			
			return true;
		}

		private void bookmark_selected() {

			var selected = this.bookmark_view.get_selection();
			if (selected.count_selected_rows()!=0) {
				TreeModel model;
				TreeIter iter;
				selected.get_selected(out model, out iter);
				GLib.Value spath;
				model.get_value(iter,2,out spath);
				var final_path = spath.get_string();
				this.current_path=final_path;
				this.refresh_icons();
				this.refresh_path_list();
				this.set_scroll_top();
			}
		}
		
		private bool on_click(Gdk.EventButton event) {

			if (event.button!=3) {
				return false;
			}
			this.menu=new Menu();
			
			MenuItem item1;
			if (this.show_hiden) {
				item1 = new MenuItem.with_label(_("Don't show hiden files"));
			} else {
				item1 = new MenuItem.with_label(_("Show hiden files"));
			}
			item1.activate.connect(this.toggle_show_hide);
			this.menu.append(item1);

			this.menu.show_all();
			this.menu.popup(null,null,null,2,Gtk.get_current_event_time());
			return true;
		}

		private void toggle_show_hide() {

			this.show_hiden = this.show_hiden ? false : true;
			
			this.refresh_icons ();
		}
		
		public void set_backup_time(time_t backup) {
			
			this.current_backup=backup;
			this.path_model.clear();
			if (this.timer_refresh!=0) {
				Source.remove(this.timer_refresh);
			}
			this.timer_refresh=Timeout.add(50,this.timer_f);
					
		}

		public bool timer_f() {

			this.refresh_icons();
			return false;
		}

		public bool selection_made(EventButton event) {
	
			if (event.type==EventType.2BUTTON_PRESS) {
		
				Gee.ArrayList<string> files;
				Gee.ArrayList<string> folders;
		
				get_selected_items(out files,out folders);
			
				if ((files.size!=0)||(folders.size!=1)) {
					return false;
				}
			
				var newfolder=folders.get(0);
			
				this.current_path=Path.build_filename(this.current_path,newfolder);
				this.refresh_icons();
				this.refresh_path_list();
				this.set_scroll_top();
			
			}
			return false;
		}

		public void get_selected_items(out Gee.ArrayList<string> files_selected, out Gee.ArrayList<string> folders_selected) {
	
			var selection = this.path_view.get_selected_items();
			TreeIter iter;
			var model = this.path_view.model;
			GLib.Value path;
			GLib.Value isfolder;

			files_selected = new Gee.ArrayList<string>();
			folders_selected = new Gee.ArrayList<string>();
	
			foreach (var v in selection) {

				model.get_iter(out iter,v);
				model.get_value(iter,2,out isfolder);
				model.get_value(iter,0,out path);
				if (isfolder.get_boolean()==true) {
					folders_selected.add(path.get_string());
				} else {
					files_selected.add(path.get_string());
				}
			}
		}

		public string get_current_path() {
			
			return (this.current_path);
			
		}

		private void refresh_path_list() {
	
			foreach (ToggleButton b in this.path_list) {
				b.destroy();
			}

			var btn = new ToggleButton.with_label("/");
			btn.show();
			btn.released.connect(this.change_path);
			this.buttons_path.pack_start(btn,false,false,0);
			this.path_list.add(btn);
		
			var elements=this.current_path.split("/");
			foreach (string s in elements) {
				if (s=="") {
					continue;
				}
				btn = new ToggleButton.with_label(s);
				btn.show();
				btn.released.connect(this.change_path);
				this.buttons_path.pack_start(btn,false,false,0);
				this.path_list.add(btn);
			}
		
			btn.active=true;
			btn.has_focus=true;
			Gtk.Requisition req;
			this.buttons_path.size_request(out req);
			Gtk.Requisition req2;
			this.size_request(out req2);
			if (req.width>=req2.width) {
				this.btn_prev.show();
				this.btn_next.show();
				this.btn_prev.size_request(out req);
				this.buttons_path.width_request=req2.width-2*req.width-10;
			} else {
				this.btn_prev.hide();
				this.btn_next.hide();
			}
	
		}
	
		private void set_scroll_top() {
	
			this.scroll.hadjustment.value=this.scroll.hadjustment.lower;
			this.scroll.vadjustment.value=this.scroll.vadjustment.lower;
	
		}

		public void change_path(Widget btn) {
	
			string fpath="";
			bool found;
	
			found = false;
			foreach (ToggleButton b in this.path_list) {
		
				if (!found) {
					fpath = Path.build_filename(fpath,b.label);
				}
				if (b!=btn) {
					b.active=false;
				} else {
					found=true;
				}
			}
			this.current_path=fpath;
			this.refresh_icons();
			this.set_scroll_top();
		}

		public static int mysort_files(file_info? a, file_info? b) {
		
			if (a.name>b.name) {
				return 1;
			}
		
			if (a.name<b.name) {
				return -1;
			}
			return 0;
		}

		private void refresh_icons() {
	
			TreeIter iter;
			Gee.List<file_info?> files;
			string title;
	
			this.path_model.clear();
			
			if (false==this.backend.get_filelist(this.current_path,this.current_backup, out files, out title)) {
				return;
			}
			
			files.sort(mysort_files);
		
			var pbuf = this.path_view.render_icon(Stock.DIRECTORY,IconSize.DIALOG,"");
		
			foreach (file_info f in files) {

				if ((this.show_hiden==false)&&(f.name[0]=='.')) {
					continue;
				}
				
				if (f.isdir) {
					this.path_model.append (out iter);
					this.path_model.set (iter,0,f.name);
					this.path_model.set (iter,1,pbuf);
					this.path_model.set (iter,2,true);
				}

			}

			pbuf = this.path_view.render_icon(Stock.FILE,IconSize.DIALOG,"");

			foreach (file_info f in files) {

				if ((this.show_hiden==false)&&(f.name[0]=='.')) {
					continue;
				}
				
				if (f.isdir) {
					continue;
				}

				this.path_model.append (out iter);
				this.path_model.set (iter,0,f.name);
				this.path_model.set (iter,1,pbuf);
				this.path_model.set (iter,2,false);

			}

		}

	}
}
