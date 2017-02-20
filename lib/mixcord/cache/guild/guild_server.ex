defmodule Mixcord.Cache.Guild.GuildServer do
  @moduledoc """
  Module for interacting with Guild Servers.
  """

  use GenServer
  alias Mixcord.Cache.Guild.GuildRegister
  alias Mixcord.Struct.{Emoji, Guild, Member, Role}
  alias Mixcord.{Shard, Util}
  require Logger

  @doc false
  def start_link(id, guild) do
    GenServer.start_link(__MODULE__, [id, guild])
  end

  @doc false
  def init([id, guild]) do
    case Registry.register(GuildRegistry, id, self()) do
      {:ok, _pid} ->
        {:ok, guild}
      {:error, error} ->
        # Causes start_link to return {:error, reason}
        {:stop, error}
    end
  end

  @spec get(id: integer) :: Mixcord.Struct.Guild.t
  @spec get(message: Mixcord.Struct.Message.t) :: Mixcord.Struct.Guild.t
  def get(id: id) do
    case GuildRegister.lookup(id) do
      {:ok, pid} ->
        {:ok, GenServer.call(pid, {:get, :guild})}
      error ->
        error
    end
  end

  def get(message: message) do
    case GuildRegister.lookup(message.channel.guild_id) do
      {:ok, pid} ->
        {:ok, GenServer.call(pid, {:get, :guild})}
      error ->
        error
    end
  end

  def get!(id: id) do
    get(id: id)
      |> Util.bangify_find(id, __MODULE__)
  end

  def get!(message: message) do
    get(message: message)
      |> Util.bangify_find(message, __MODULE__)
  end

  def call(id, request) do
    with \
      {:ok, pid} <- GuildRegister.lookup(id),
      res <- GenServer.call(pid, request),
    # res will be a tuple
    do: {:ok, res}
  end

  def create(%{unavailable: true} = guild) do
    :ets.insert(:unavailable_guilds, {guild.id, guild})
  end

  @doc false
  def create(guild) do
    # This returns {:ok, guild} or {:error reason}
    GuildRegister.create_guild_process(guild.id, guild)
  end

  @doc false
  def create(guild, shard_pid) do
    Shard.request_guild_members(shard_pid, guild.id)
    create(guild)
  end

  @doc false
  def update(guild) do
    call(guild.id, {:update, :guild, guild})
  end

  @doc false
  def delete(guild_id) do
    call(guild_id, {:delete, :guild})
  end

  @doc false
  def member_add(guild_id, member) do
    call(guild_id, {:create, :member, member})
  end

  @doc false
  def member_update(guild_id, user, _nick, roles) do
    call(guild_id, {:update, :member, user, roles})
  end

  @doc false
  def member_remove(guild_id, user) do
    call(guild_id, {:delete, :member, user})
  end

  @doc false
  def role_create(guild_id, role) do
    call(guild_id, {:create, :role, role})
  end

  @doc false
  def role_update(guild_id, role) do
    call(guild_id, {:update, :role, role})
  end

  @doc false
  def role_delete(guild_id, role_id) do
    call(guild_id, {:delete, :role, role_id})
  end

  @doc false
  def emoji_update(guild_id, emojis) do
    call(guild_id, {:update, :emoji, emojis})
  end

  def handle_call({:get, :guild}, _from, state) do
    {:reply, {Guild.to_struct(state)}, state}
  end

  def handle_call({:update, :guild, guild}, _from, state) do
    {:reply, {Guild.to_struct(state), Guild.to_struct(guild)}, guild}
  end

  def handle_call({:delete, :guild}, _from, state) do
    {:stop, :normal, Guild.to_struct(state), %{}}
  end

  def handle_call({:create, :member, member}, _from, state) do
    new_members = [member | state.members]
    {:reply, {Member.to_struct(member)}, %{state | members: new_members}}
  end

  def handle_call({:update, :member, user, roles}, _from, state) do
    member_index = Enum.find_index(state.members, fn member ->
      member.user.id == user.id
    end)
    old_member =
      case Enum.fetch(state.members, member_index) do
        {:ok, old_member} -> old_member
        :error -> %{user: %{}, roles: []}
      end
    new_members = List.update_at(state.members, member_index, fn member ->
      %{member | user: user, roles: roles}
    end)

    {:reply, {Member.to_struct(old_member), Member.to_struct(%{old_member | user: user, roles: roles})}, %{state | members: new_members}}
  end

  def handle_call({:delete, :member, user}, _from, state) do
    member_index = Enum.find_index(state.members, fn member -> member.user.id == user.id end)
    deleted_member =
      case Enum.fetch(state.members, member_index) do
        {:ok, deleted_member} -> deleted_member
        :error -> %{}
      end
    members = List.delete_at(state.members, member_index)
    {:reply, {Member.to_struct(deleted_member)}, %{state | members: members}}
  end

  def handle_call({:create, :role, role}, _from, state) do
    new_roles = [role | state.roles]
    {:reply, {Role.to_struct(role)}, %{state | roles: new_roles}}
  end

  def handle_call({:update, :role, role}, _from, state) do
    role_index = Enum.find_index(state.roles, fn g_role -> g_role.id == role.id end)
    old_role =
      case Enum.fetch(state, role_index) do
        {:ok, role} -> role
        :error -> %{}
      end
    roles = List.update_at(state.roles, role_index,
      fn _ ->
        role
      end)
      IO.inspect old_role
      IO.inspect role
    {:reply, {Role.to_struct(old_role), Role.to_struct(role)}, %{state | roles: roles}}
  end

  def handle_call({:delete, :role, role_id}, _from, state) do
    role_index = Enum.find_index(state.roles, fn g_role -> g_role.id == role_id end)
    old_role =
      case Enum.fetch(state, role_index) do
        {:ok, role} -> role
        :error -> %{}
      end
    roles = List.delete_at(state.roles, role_index)
    {:reply, {Role.to_struct(old_role)}, %{state | roles: roles}}
  end

  def handle_call({:update, :emoji, emojis}, _from, state) do
    old_emojis = state.emojis
    {:reply, {Emoji.to_struct(old_emojis), Emoji.to_struct(emojis)}, %{state | emojis: emojis}}
  end

end