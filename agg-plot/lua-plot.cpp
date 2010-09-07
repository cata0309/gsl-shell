
/* lua-plot.cpp
 * 
 * Copyright (C) 2009, 2010 Francesco Abbate
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or (at
 * your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 */

extern "C" {
#include "lua.h"
#include "lauxlib.h"
}

#include "lua-plot.h"
#include "lua-plot-cpp.h"
#include "win-plot-refs.h"
#include "window.h"
#include "gs-types.h"
#include "lua-utils.h"
#include "object-refs.h"
#include "lua-cpp-utils.h"
#include "lua-draw.h"
#include "colors.h"
#include "plot.h"
#include "drawable.h"
#include "resource-manager.h"
#include "agg-parse-trans.h"

__BEGIN_DECLS

static int plot_new        (lua_State *L);
static int plot_add        (lua_State *L);
static int plot_update     (lua_State *L);
static int plot_flush      (lua_State *L);
static int plot_add_line   (lua_State *L);
static int plot_index      (lua_State *L);
static int plot_newindex   (lua_State *L);
static int plot_free       (lua_State *L);
static int plot_show       (lua_State *L);
static int plot_title_set  (lua_State *L);
static int plot_title_get  (lua_State *L);
static int plot_units_set  (lua_State *L);
static int plot_units_get  (lua_State *L);

static int canvas_new      (lua_State *L);

static int  plot_add_gener (lua_State *L, bool as_line);

static const struct luaL_Reg plot_functions[] = {
  {"plot",        plot_new},
  {"canvas",      canvas_new},
  {NULL, NULL}
};

static const struct luaL_Reg plot_methods[] = {
  {"add",         plot_add        },
  {"addline",     plot_add_line   },
  {"update",      plot_update     },
  {"show",        plot_show       },
  {"__index",     plot_index      },
  {"__newindex",  plot_newindex   },
  {"__gc",        plot_free       },
  {NULL, NULL}
};

static const struct luaL_Reg plot_properties_get[] = {
  {"title",        plot_title_get  },
  {"units",        plot_units_get  },
  {NULL, NULL}
};

static const struct luaL_Reg plot_properties_set[] = {
  {"title",        plot_title_set  },
  {"units",        plot_units_set  },
  {NULL, NULL}
};

__END_DECLS

int
plot_new (lua_State *L)
{
  typedef plot_auto<drawable, lua_management> plot_type;
  lua_plot *p = push_new_object<plot_type>(L, GS_PLOT);

  if (lua_isstring (L, 1))
    {
      const char *title = lua_tostring (L, 1);
      if (title)
	p->set_title(title);
    }

  return 1;
}

int
canvas_new (lua_State *L)
{
  lua_plot *p = push_new_object<lua_plot>(L, GS_PLOT);

  if (lua_isstring (L, 1))
    {
      const char *title = lua_tostring (L, 1);
      if (title)
	p->set_title(title);
    }

  return 1;
}

int
plot_free (lua_State *L)
{
  return object_free<lua_plot>(L, 1, GS_PLOT);
}

int
plot_add_gener (lua_State *L, bool as_line)
{
  lua_plot *p = object_check<lua_plot>(L, 1, GS_PLOT);
  drawable *obj = parse_graph_args (L);
  agg::rgba8 *color = check_color_rgba8 (L, 3);

  object_ref_add (L, 1, 2);

  AGG_LOCK();

  p->add(obj, color, as_line);

  AGG_UNLOCK();

  plot_flush (L);

  return 0;
}
 
int
plot_add (lua_State *L)
{
  return plot_add_gener (L, false);
}
 
int
plot_add_line (lua_State *L)
{
  return plot_add_gener (L, true);
}

int
plot_title_set (lua_State *L)
{
  lua_plot *p = object_check<lua_plot>(L, 1, GS_PLOT);
  const char *title = lua_tostring (L, 2);

  if (title == NULL)
    return gs_type_error (L, 2, "string");
	  
  AGG_LOCK();
  p->set_title(title);
  AGG_UNLOCK();

  plot_update (L);
	  
  return 0;
}

int
plot_title_get (lua_State *L)
{
  lua_plot *p = object_check<lua_plot>(L, 1, GS_PLOT);

  AGG_LOCK();

  const char *title = p->title();
  lua_pushstring (L, title);

  AGG_UNLOCK();
  
  return 1;
}

int
plot_units_set (lua_State *L)
{
  lua_plot *p = object_check<lua_plot>(L, 1, GS_PLOT);
  bool request = (bool) lua_toboolean (L, 2);

  AGG_LOCK();
  
  bool current = p->use_units();

  if (current != request)
    {
      p->set_units(request);
      AGG_UNLOCK();
      plot_update (L);
    }
  else
    {
      AGG_UNLOCK();
    }
	  
  return 0;
}

int
plot_units_get (lua_State *L)
{
  lua_plot *p = object_check<lua_plot>(L, 1, GS_PLOT);

  AGG_LOCK();
  lua_pushboolean (L, p->use_units());
  AGG_UNLOCK();

  return 1;
}

int
plot_index (lua_State *L)
{
  return mlua_index_with_properties (L, plot_properties_get, false);
}

int
plot_newindex (lua_State *L)
{
  return mlua_newindex_with_properties (L, plot_properties_set);
}

int
plot_update (lua_State *L)
{
  lua_plot *p = object_check<lua_plot>(L, 1, GS_PLOT);
  window_plot_rev_lookup_apply (L, 1, window_slot_update);
  p->redraw_done();
  return 0;
}

int
plot_flush (lua_State *L)
{
  lua_plot *p = object_check<lua_plot>(L, 1, GS_PLOT);
  window_plot_rev_lookup_apply (L, 1, window_slot_refresh);
  p->redraw_done();
  return 0;
}

int
plot_show (lua_State *L)
{
  lua_pushcfunction (L, window_attach);
  window_new (L);
  lua_pushvalue (L, 1);
  lua_pushstring (L, "");
  lua_call (L, 3, 0);
  return 0;
}

void
plot_register (lua_State *L)
{
  /* plot declaration */
  luaL_newmetatable (L, GS_METATABLE(GS_PLOT));
  luaL_register (L, NULL, plot_methods);
  lua_pop (L, 1);

  /* gsl module registration */
  luaL_register (L, NULL, plot_functions);
}
