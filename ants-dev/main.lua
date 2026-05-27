local push = require "push"

local gameWidth, gameHeight = 1080, 720 --fixed game resolution
local windowWidth, windowHeight = love.window.getDesktopDimensions()

local function sigmoid(x)
    return 1 / (1 + math.exp(-x))
end

Ant = {}

function Ant:new(x, y, facing)

   local o = {}
   setmetatable(o, self)
   self.__index = self

   o.mode = "walk"

   o.x = x
   o.y = y
   o.facing = facing
   o.prev_facing = facing
   
   o.time = 0
   o.assess_cooldown = 2 -- happier ants should adjust this up
   o.assess_duration = 0.5 -- happier ants should adjust this down
   o.smell_duration = 0.25 -- fixed (presumably by biology)
   o.smell_count = 0 -- look I need it ok
   o.happy = 1
   o.prev_happy = 1

   o.speed = 10

   o.trail_amount = 0.03 -- amount of trail pheromone to leave

   o.antenna_size = 7 -- cm?
   o.antenna_arot = -math.pi/6
   o.antenna_brot = math.pi/6

   o.abs_radius = 4
   o.thorax_len = 7
   o.head_radius = 4

   return o
   
end

function Ant:assess(dt)

   -- re-establish facing direction
   -- draw from gaussian with variance = sigmoid(1/happiness)
   -- (small variance if happy, wider if not)

   -- alternate: compare antenna A/B, weight turn in happier direction
   -- and make turning angle smaller if happier (with maybe sigmoid)

   -- smell once, and if there's time, turn and smell again

   if self.time > self.smell_count * self.smell_duration then

      local happy_a, happy_b = self:smell()
      self.smell_count = self.smell_count + 1

      self.happy = (happy_a + happy_b) / 2 -- Maybe some memory?
      self.assess_cooldown = 3 * sigmoid(self.happy)
      self.assess_duration = 3 * sigmoid(-self.happy)

      local turn_angle = math.pi / 2 * sigmoid(-self.happy)
      local turn_direction

      if happy_a * happy_b > 0 then
	 -- same sign
	 local check = math.abs(happy_a)/(math.abs(happy_a)+math.abs(happy_b))
	 if math.random() > check then
	    turn_direction = 1
	 else
	    turn_direction = -1
	 end
	 
      elseif happy_a > 0 then
	 -- b is negative
	 turn_direction = 1
      else
	 turn_direction = -1
      end
            
      self.facing = self.facing + turn_direction * turn_angle
   end
 
end

function Ant:smell()

   -- check what pheromones are under the antennae
   local happy_a, happy_b = 0, 0
   local anta_x, anta_y, antb_x, antb_y = self:get_antennae_pos()

   for i, phero in ipairs(World.pheros) do
      happy_a = happy_a + phero.ant_happy_factor * phero:get(anta_x, anta_y)
      happy_b = happy_b + phero.ant_happy_factor * phero:get(antb_x, antb_y)
   end

   return happy_a, happy_b   

end

function Ant:probe()

   -- check what objects are under the antennae
   
end

function Ant:grab()

  -- put this as some component in ecs so player has same grab? later
   
end

function Ant:new_facing()

   -- depricated (for now)

   self.facing = love.math.randomNormal(1 / self.happy, self.facing)
   
end

function Ant:update(dt)

   self.time = self.time + dt

   if self.mode ~= "assess" then

      if self.time >= self.assess_cooldown then
	 self.time = 0	
	 self.mode = "assess"
      end

   end
   
   if self.mode == "walk" then

      self.x = self.x + self.speed * dt * math.cos(self.facing)
      self.y = self.y + self.speed * dt * math.sin(self.facing)

      World.pheros[3]:add(self.x, self.y, self.trail_amount)

   end

   if self.mode == "assess" then

      self:assess(dt)

      if self.time >= self.assess_duration then
	 self.time = 0
	 self.smell_count = 0
	 self.mode = "walk"
      end
      
   end   
   
end

function Ant:get_head_pos()

   -- return location of the head center

   local head_x = self.x + self.thorax_len * math.cos(self.facing)
   local head_y = self.y + self.thorax_len * math.sin(self.facing) 

   return head_x, head_y
end

function Ant:get_antennae_pos()

   -- return location of the antenna ends

   local head_x, head_y, anta_x, anta_y, antb_x, antb_y
   head_x, head_y = self:get_head_pos()

   anta_x = head_x + self.antenna_size * math.cos(self.facing + self.antenna_arot)
   anta_y = head_y + self.antenna_size * math.sin(self.facing + self.antenna_arot)
   antb_x = head_x + self.antenna_size * math.cos(self.facing + self.antenna_brot)
   antb_y = head_y + self.antenna_size * math.sin(self.facing + self.antenna_brot)

   return anta_x, anta_y, antb_x, antb_y

end

function Ant:draw()

   love.graphics.setColor(love.math.colorFromBytes(210,180,140))

   love.graphics.circle("fill", self.x, self.y, self.abs_radius)
   head_x, head_y = self:get_head_pos()
   love.graphics.circle("fill", head_x, head_y, self.head_radius)
   anta_x, anta_y, antb_x, antb_y = self:get_antennae_pos()
   love.graphics.line(head_x, head_y, anta_x, anta_y)
   love.graphics.line(head_x, head_y, antb_x, antb_y)
   
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

function Phero:new(gridx, gridy, D, evap_rate, color, ant_happy_factor)

   local o = {}
   setmetatable(o, self)
   self.__index = self

   -- add name and allegience as fields later

   o.visible = true
   o.color = color

   o.ant_happy_factor = ant_happy_factor

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

function Phero:get(x, y)

   local i = math.floor(x/self.gridx) + 1
   local j = math.floor(y/self.gridy) + 1
   
   return self.densities:iloc(i,j) or 0
   
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
	 love.graphics.setColor(self.color[1], self.color[2], self.color[3], alpha)
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

   alarm_phero = Phero:new(25, 25, 1, 0.5, {1,0,0}, -5)
   table.insert(World.pheros, alarm_phero)

   food_phero = Phero:new(20, 20, 1, 0.5, {0.5,1,0.1}, 3)
   table.insert(World.pheros, food_phero)

   trail_phero = Phero:new(3, 3, 0.01, 0, {0, 1, 1}, 1)
   table.insert(World.pheros, trail_phero)

   text = "not ok"
   --text = World.pheros[1].densities.thresh
end

function love.update(dt)

   if #World.ants > 0 then
      --text = math.pi / 2 * sigmoid(-World.ants[1].happy)
      --text = World.ants[1].smell_count
      --text = World.ants[1].time
      local ant = World.ants[1]
      text = string.format("%f\n%f\n%f\n", ant.happy, ant.assess_cooldown, ant.assess_duration)
   end
   

   for _, ant in ipairs(World.ants) do
      ant:update(dt)
   end
   
   for _, phero in ipairs(World.pheros) do
      phero:update(dt)
   end

   if love.mouse.isDown(1) then
      x, y = love.mouse.getPosition( )
      World.pheros[3]:add(x,y,1)
   end

   
   if love.mouse.isDown(2) then
      x, y = love.mouse.getPosition( )
      World.pheros[2]:add(x,y,5)
   end

   if love.mouse.isDown(3) then
      x, y = love.mouse.getPosition( )
      World.pheros[1]:add(x,y,10)
   end


   --text = trail_phero:get_total()
   
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
      World.pheros[1]:add(x,y,1)
   end

   if button == 5 then
      local new_ant = Ant:new(x,y,math.random(0,2*math.pi))
      table.insert(World.ants, new_ant)
   end
      
end
