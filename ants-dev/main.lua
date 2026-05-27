local push = require "push"

local gameWidth, gameHeight = 1080, 720 --fixed game resolution
local windowWidth, windowHeight = love.window.getDesktopDimensions()

Ant = {}

function Ant:new(x, y, facing)

   local o = {}
   setmetatable(o, self)
   self.__index = self


   o.x = x
   o.y = y
   o.facing = facing
   o.prev_facing = facing

   o.assess_period = 2 
   o.until_assess = o.assess_period -- s
   o.assess_duration = 1 -- happier ants should adjust this down
   o.prev_happy = 0

   o.antenna_size = 0.1 -- cm?

   return o
   
end

function Ant:assess()

   -- re-establish facing direction
   -- draw from gaussian with variance = sigmoid(1/happiness)
   -- (small variance if happy, wider if not)

   
end

function Ant:probe()

   -- check what's under the antennae
   
end

function Ant:grab()

  -- put this as some component in ecs so player has same grab? later
   
end


function Ant:update(dt)

   self.until_assess = self.until_assess - dt
   if self.until_assess <= 0 then
      self.until_assess = self.assess_period
      self:assess()
      -- some waiting animation for a bit?
   end
   
   
end

function Ant:draw()
end

SparseArray = {}

function SparseArray:new(width, thresh)
   
   local o = {}
   setmetatable(o, self)
   self.__index = self

   o.array = {}
   o.w = width
   o.thresh = thresh

   return o
end

function SparseArray:get_nonnil_inds()
   -- get all indices with non-nil values
   local is = {}
   local js = {}
   for k,_ in pairs(self.array) do
      i = math.floor((k-1)/self.w) + 1
      j = k%self.w
      table.insert(is, i)
      table.insert(js, j)
   end
   return is, js
end

function SparseArray:insert(i, j, val)
   local index = (i-1)*self.w + j
   if val >= self.thresh then
      self.array[index] = val
   else
      self.array[index] = nil
   end
end

function SparseArray:iloc(i,j)
   local index = (i-1)*self.w + j
   return self.array[index]
end

function SparseArray:add(i,j,val)
   self:insert(i,j,val + (self:iloc(i,j) or 0))
end

function SparseArray:laplacian(i,j)

   local total = 0
   total = total + (self:iloc(i-1,j) or 0)
   total = total + (self:iloc(i+1,j) or 0)
   total = total + (self:iloc(i,j-1) or 0)
   total = total + (self:iloc(i,j+1) or 0)
   total = total - 4 * (self:iloc(i,j) or 0)
   return total
   
end

Phero = {}

function Phero:new(gridx, gridy, D, evap_rate, color)

   local o = {}
   setmetatable(o, self)
   self.__index = self

   -- add name and allegience as fields later

   o.visible = true
   o.color = color

   o.gridx = gridx -- cell width in px
   o.gridy = gridy -- cell height in px

   o.D = D
   o.evap_rate = evap_rate

   o.threshold = 0.01 * D
   o.densities = SparseArray:new(math.ceil(gameWidth/o.gridx), o.threshold)

   return o
   
end

function Phero:add(x, y, amount)
   
   local i = math.floor(x/self.gridx) + 1
   local j = math.floor(y/self.gridy) + 1
   
   self.densities:add(i,j,amount)
   
end

function Phero:get_total()
   local is, js = self.densities:get_nonnil_inds()
   local tot = 0
   for i = 1, #is do
      tot = tot + (self.densities:iloc(is[i], js[i]) or 0)
   end
   return tot
end



function Phero:diffuse(dt)

   -- implementing Fick's laws for diffusion
   -- evaporate first then diffuse on grid (both simult. would violate conservation)

   -- make an array of proposed changes
   local density_changes = SparseArray:new(self.densities.w, -1*math.huge)
   local is, js = self.densities:get_nonnil_inds()

   -- flux upwards (Fick's first law)
   -- approx flux = D * dt * density * evap_rate
   for i = 1, #is do      
      density_changes:insert(is[i], js[i], -1 * self.D * dt * self.evap_rate * (self.densities:iloc(is[i],js[i]) or 0))
   end

   -- apply changes
   for i = 1, #is do
      self.densities:add(is[i], js[i], density_changes:iloc(is[i], js[i]) or 0)
   end

   -- 2D diffusion
   -- start with fresh changes array
   local density_changes = SparseArray:new(self.densities.w, -1*math.huge)
   local dis = {0,-1,1,0,0}
   local djs = {0,0,0,-1,1}
   -- approx dphi = D * dt * Laplacian(phi)
   for i = 1, #is do
      for ii = 1, 5 do
	 density_changes:add(is[i]+dis[ii], js[i]+djs[ii], self.D * dt * self.densities:laplacian(is[i]+dis[ii], js[i]+djs[ii]))
      end
   end

   visited_is, visited_js = density_changes:get_nonnil_inds()

   -- apply changes
   for i = 1, #visited_is do
      self.densities:add(visited_is[i], visited_js[i], density_changes:iloc(visited_is[i], visited_js[i]) or 0)
   end

      
end

function Phero:update(dt)

   self:diffuse(dt)
   
end

function Phero:draw()

   -- TODO scale with push library
   -- TODO zoom
   -- TODO pan (draw to canvas then apply camera transforms?)

   if self.visible then
      is, js = self.densities:get_nonnil_inds()
      for i = 1, #is do
	 local alpha = math.min(1, (self.densities:iloc(is[i], js[i]) or 0)/10)
	 love.graphics.setColor(0,1,1, alpha)
	 local x = (is[i]-1) * self.gridx
	 local y = (js[i]-1) * self.gridy -- may need centering?
	 love.graphics.rectangle("fill", x, y, self.gridx, self.gridy)
      end
   end
end


World = {
   ants = {},
   pheros = {}
}

function love.load()

   -- gridx, gridy, D, evap_rate, color
   trail_phero = Phero:new(10, 10, 0.1, 0, {0, 1, 1})
   table.insert(World.pheros, trail_phero)

   text = "not ok"
   text = World.pheros[1].densities.thresh
   
end

function love.update(dt)

   for _, ant in ipairs(World.ants) do
      ant:update(dt)
   end
   
   for _, phero in ipairs(World.pheros) do
      phero:update(dt)
   end

   if love.mouse.isDown(1) then
      x, y = love.mouse.getPosition( )
      World.pheros[1]:add(x,y,1)
   end

   text = trail_phero:get_total()
   
end


function love.draw()

   love.graphics.setColor(1,1,1)
   --love.graphics.clear()

   love.graphics.print(text, 400, 300)

   for _, ant in ipairs(World.ants) do
      ant:draw()
   end
   for _, phero in ipairs(World.pheros) do
      phero:draw()
   end
   
end

function love.mousepressed(x, y, button, istouch)
   
   if button == 1 then
      -- TODO only registers on x = y lines, with top left errorring.. something funny here.
      World.pheros[1]:add(x,y,1)
   end

   if button == 2 then
      local new_ant = Ant:new(x,y,math.random(0,2*math.pi))
      table.insert(World.ants, new_ant)
   end
      
end
